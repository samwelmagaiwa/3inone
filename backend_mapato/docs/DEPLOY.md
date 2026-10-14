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
7. **Regions, districts, wards** (the lists in *Add Property* and the registration form): they are NOT created by the
   migrations. Run `docker exec 3inone_backend php artisan locations:import` once (details below). Skipping this
   leaves every Region / District / Ward picker empty, with no error.
8. **Check**: `https://3inone.nexoryatech.com/api/health` answers `200`, and
   `https://3inone.nexoryatech.com/api/locations/regions` lists 31 regions.
9. **The app**: `boda_mapato/lib/config/api_config.dart` selects `Environment.threeInOne`
   (`https://3inone.nexoryatech.com/api`, and the web address without `/api`); rebuild the app and sign in again.
   The older depot server stays available as `Environment.production`.

## Regions, districts and wards: `locations:import`

The pickers read the tables `states` (regions), `lgas` (districts), `wards`, `villages` (streets) and `places`,
which are filled from the 31 CSV files in `backend_mapato/location-files/` (they are inside the Docker image).
The live server had these tables **empty** until 2026-10-14, which is why the Region list in *Add Property* could not
be opened.

```bash
docker exec 3inone_backend php artisan locations:import --dry-run    # read the files, say what is in them, change nothing
docker exec 3inone_backend php artisan locations:import --if-empty   # load only while there are no regions (deploy.sh does this)
docker exec 3inone_backend php artisan locations:import              # add whatever is missing
```

It only ever **adds** rows (never updates or deletes one), does it in one transaction (a failure leaves the tables
untouched), and a second run adds nothing. Loading takes about half a minute. Names are tidied on the way in: the
source has line breaks inside names (`"DODOMA⏎CBD"`), doubled spaces, a district broken mid-word (`WANGING'O⏎MBE`
= Wanging'ombe) and `DAR-ES-SALAAM` (loaded as *Dar es Salaam*, the spelling the rest of the app uses); the rules are in
`App\Support\LocationImporter` and are pinned by `tests/Feature/LocationImportTest.php`. `deploy.sh` runs the
`--if-empty` form after the migrations and `./deploy.sh status` prints how many regions the server has.

**Known gap in the data:** the five Zanzibar and Pemba files (`mjini_magharibi`, `pemba_kaskazini`, `pemba_kusini`,
`unguja_kaskazini`, `unguja_kusini`) hold only the 11 districts, with ONE placeholder ward and street each. The other
26 regions are complete. Ward is optional in the app, so Zanzibar addresses still work, but the real shehia lists need
adding to those files (same 8 columns) and `locations:import` run again; it will add them next to what is there.

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

## Updating later: `backend_mapato/deploy.sh`

Run it from `backend_mapato/` on your machine (it needs `ssh` and `curl`; `deploy` also needs Docker). It only ever
touches the 3inone stack above, and it pushes to the `threeinone` git remote, never to `origin`.

| Command | What it does |
|---|---|
| `./deploy.sh release ["message"]` | commits the backend folder, pushes to GitHub, waits until the workflow has tested the code and pushed the image (it looks for the image tagged with your commit on Docker Hub, up to 25 minutes), then rolls it out |
| `./deploy.sh update` | rolls out the image that is on Docker Hub now |
| `./deploy.sh deploy` | builds the image on your machine, pushes it as `:latest` and as `:local-<time>-<sha>`, rolls it out. **Skips the tests**: for emergencies |
| `./deploy.sh migrate` / `backup` | back up the database and migrate / only back up |
| `./deploy.sh status` | read-only: container, image, pending migrations, number of regions loaded, health |

"Rolling out" is: refresh `docker-compose.yml` on the server if the repo's `docker-compose.prod.yml` differs (the old
copy is kept as `.bak`), `docker compose pull && up -d`, wait for `/api/health`, **if migrations are pending: dump the
database to `/www/3inone/backups/` (stops if the dump is not complete), then `migrate --force`**, load the regions /
districts / wards if the server has none (`locations:import --if-empty`), `config:cache`, `route:cache`. `SKIP_MIGRATE=1` leaves pending migrations alone. Backups are not pruned: delete old ones by hand.

The same by hand:

```bash
cd /www/3inone
docker compose pull && docker compose up -d
docker exec 3inone_backend php artisan migrate --force     # only if the release has new migrations (back up first)
docker exec 3inone_backend php artisan config:cache && docker exec 3inone_backend php artisan route:cache
curl -s -o /dev/null -w '%{http_code}\n' https://3inone.nexoryatech.com/api/health
```

Every push to `master` that touches `backend_mapato/` is tested and, if the tests pass, built as a new `:latest`
and `:<sha>`. To go back to a known build, set `image: magaiwa/3inone-backend:<sha>` in the compose file and run
`docker compose up -d`.

## Check against MariaDB before a release

The tests and CI run on SQLite, which forgives things the server's MariaDB refuses; MySQL 8 forgives some of them
too. Two mistakes got through that way (a hand-written `GROUP BY` list that missed the new `owner_id` column, so
categories, brands, customers and suppliers answered 500; and an ISO-8601 time with a zone suffix written into a
`DATETIME`, so a sale with a payment could not be saved). Before a release that touches queries or dates, run the
whole suite against a throwaway MariaDB of the same version on its own private network:

```powershell
docker network create mt_verify_net
docker run -d --name mt_verify_mariadb --network mt_verify_net -e MARIADB_ROOT_PASSWORD=verify_only -e MARIADB_DATABASE=mt_verify mariadb:10.11 --character-set-server=utf8mb4 --collation-server=utf8mb4_general_ci
# wait until `docker exec mt_verify_mariadb mariadb -uroot -pverify_only -e "select 1"` answers
docker run --rm --network mt_verify_net --entrypoint php -v "<project>ackend_mapato:/var/www/html" -w /var/www/html `
  -e APP_ENV=testing -e DB_CONNECTION=mysql -e DB_HOST=mt_verify_mariadb -e DB_PORT=3306 -e DB_DATABASE=mt_verify `
  -e DB_USERNAME=root -e DB_PASSWORD=verify_only -e CACHE_STORE=array -e SESSION_DRIVER=array -e QUEUE_CONNECTION=sync `
  backend_mapato-app artisan test
docker rm -f mt_verify_mariadb; docker network rm mt_verify_net
```

`TestEnvironmentSafetyTest` is expected to fail there (it asserts SQLite) and a few SQLite-only tests skip. Anything
else that fails is a real MariaDB problem. Never point `DB_HOST` at the real database.

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
