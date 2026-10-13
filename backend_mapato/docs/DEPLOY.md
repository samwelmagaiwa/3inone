# Deploying the 3inone backend

The backend is built by GitHub Actions (`.github/workflows/build-3inone-backend.yml`) into the Docker Hub
image **`magaiwa/3inone-backend`** (`:latest` and `:<commit sha>`) and runs on the VPS as one container.
The workflow only builds. It never touches a server and never runs migrations.

## What runs where

| | |
|---|---|
| Server | the VPS `169.58.188.122`, user `deploy` (SSH key login) |
| Folder | `/www/3inone` — `docker-compose.yml` (this repo's `docker-compose.prod.yml`) and `.env` (secrets, `chmod 600`, never in git) |
| Container | `3inone_backend`, image `magaiwa/3inone-backend:latest`, volume `3inone_storage` (uploads, logs) |
| Address | the container listens on `127.0.0.1:8087`; the panel's nginx reverse-proxies `3inone.nexoryatech.com` to it |
| Database | database `3inone`, user `3inone`, on the server's own MariaDB 10.11 (not in a container) |
| Other sites | nothing here touches `/www/depot`, `depot_backend` or the `depot` database |

Ports 8080–8086 are taken by other sites on that server; 8087 is this one's.

## First install, step by step

1. **Files and container** (done by SSH): copy `docker-compose.prod.yml` to `/www/3inone/docker-compose.yml`, create
   `.env` (below), then `docker compose pull && docker compose up -d`.
2. **`.env`** in `/www/3inone`: `APP_NAME`, `APP_URL=https://3inone.nexoryatech.com`, `APP_KEY=base64:<32 random bytes>`
   (`openssl rand -base64 32`), `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`; optional `SMS_*` and `BILLING_*`
   (see the compose file for every name and its default).
3. **Database permission** (panel: *Databases* → `3inone` → permission): the account must be allowed from the Docker
   network, not only `localhost`. Choose *specified IP* `172.17.%` (or *everyone*: the firewall already limits
   port 3306 to the server's own Docker networks and one office address).
4. **Reverse proxy** (panel: *Website* → `3inone.nexoryatech.com` → *Reverse proxy* → *Add*): proxy dir `/`,
   target URL `http://127.0.0.1:8087`, sent domain `$host`. Until this is done the site answers 403 (empty folder).
5. **SSL** (panel: the site's *SSL* tab → Let's Encrypt, then *Force HTTPS*).
6. **Migrations** (only when the database has not got the current schema; see the next section):
   `docker exec 3inone_backend php artisan migrate --force`
7. **Check**: `https://3inone.nexoryatech.com/api/health` answers `200`.
8. **The app**: set the production address in `boda_mapato/lib/config/api_config.dart` to
   `https://3inone.nexoryatech.com/api` (and the web address without `/api`), then rebuild the app.

## Migrations: back up first, and know what they do

A database at the old schema (106 migrations, latest `2026_10_08…`, no `businesses` table) needs the 13 migrations
that came with the multi-business work. Most only add columns and tables. Three move data, all recorded and none
deleting anything: they give every existing inventory row to the owner of the depot, move inventory staff who
belong to no business under that owner (the old value is kept in `tenancy_reparent_log`), and make the inventory
settings per business (the old table is kept as `inventory_settings_legacy`). Details and checks to run before and
after: `docs/TENANCY.md`, section "Deploying to the live depot".

```bash
# a dump before, next to the compose file (readable only by deploy)
umask 077; mkdir -p /www/3inone/backups
docker run --rm --network host -e MYSQL_PWD="$DB_PASSWORD" mysql:8.0 \
  mysqldump -h 127.0.0.1 -u3inone --single-transaction --routines --triggers --no-tablespaces --column-statistics=0 3inone \
  > /www/3inone/backups/3inone_before_migrate_$(date +%Y%m%d_%H%M%S).sql
```

The server database is **MariaDB**, while the migrations and the test suite were run on MySQL 8 (the app is written
for MySQL 5.7 compatibility). Rehearse the migration on a copy of the database first, or on a throwaway MariaDB
container, before running it on data that matters.

After migrating, run the ownership check and look at its result: `docker exec 3inone_backend php artisan inventory:ownership-report`.
Everyone must sign in again once, so the app learns about their business.

## Updating later

```bash
cd /www/3inone
docker compose pull && docker compose up -d
docker exec 3inone_backend php artisan migrate --force     # only if the release has new migrations
docker exec 3inone_backend php artisan config:cache && docker exec 3inone_backend php artisan route:cache
curl -s -o /dev/null -w '%{http_code}\n' https://3inone.nexoryatech.com/api/health
```

Every push to `master` that touches `backend_mapato/` is tested and, if the tests pass, built as a new `:latest`
and `:<sha>`. To go back to a known build, set `image: magaiwa/3inone-backend:<sha>` in the compose file and run
`docker compose up -d`.

## Why `network_mode: bridge`

The server's firewall drops everything by default and lets MySQL (port 3306) in per Docker network, one subnet at a
time (each site has its own rule). The default bridge network (`172.17.0.0/16`) is already allowed. A network of its
own, which Compose creates for a folder by default, gets a new subnet and is dropped (the symptom is a connection
that times out, not "access denied") until someone adds a rule such as
`iptables -A INPUT -s <subnet> -p tcp --dport 3306 -j ACCEPT`. If you prefer an isolated network, add that rule
(and keep it across reboots), then remove `network_mode: bridge` from the compose file.

## Secrets

Passwords and keys live only in `/www/3inone/.env` on the server. They are not in git, not in this file and not in
the image (`.env` is in `.dockerignore`). A password that has been pasted into a chat or a ticket should be changed.
