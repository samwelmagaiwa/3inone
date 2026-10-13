#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# deploy.sh  --  release and deploy the 3inone backend
#
#   ./deploy.sh release ["message"]  commit the backend, push to GitHub (the tests and the image build run
#                                    there), wait for the new image on Docker Hub, roll it out
#   ./deploy.sh update               roll out the image that is on Docker Hub now (:latest)
#   ./deploy.sh deploy               build the image HERE, push it to Docker Hub, roll it out.
#                                    Skips the tests the GitHub workflow runs: for emergencies.
#   ./deploy.sh migrate              back up the database, then run pending migrations
#   ./deploy.sh backup               only back up the database
#   ./deploy.sh status               read-only: what runs on the server, its health, pending migrations
#
# "Rolling out" = pull the image on the server, `docker compose up -d`, wait until /api/health answers, back up the
# database and run the migrations IF there are pending ones (set SKIP_MIGRATE=1 to leave them), refresh the
# config cache. Nothing is ever deleted: a failed migration leaves the backup next to the compose file.
#
# This script only ever touches the 3inone stack (/www/3inone, container 3inone_backend, database 3inone). The older
# depot site on the same server (/www/depot) is not in here on purpose.
#
# Settings can be overridden from the environment, for example:  SSH_KEY=~/.ssh/other ./deploy.sh status
# ---------------------------------------------------------------------------

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"        # the folder of this script = the backend (docker build context)

# -- Config -------------------------------------------------------------------------------------------------------
IMAGE_REPO="${IMAGE_REPO:-magaiwa/3inone-backend}"
IMAGE="$IMAGE_REPO:latest"

GIT_REMOTE="${GIT_REMOTE:-threeinone}"     # github.com/samwelmagaiwa/3inone -- NOT origin (the older mobile_app repo)
GIT_BRANCH="${GIT_BRANCH:-master}"
CI_WORKFLOW_FILE=".github/workflows/build-3inone-backend.yml"
CI_WAIT_SECONDS="${CI_WAIT_SECONDS:-1500}" # how long `release` waits for GitHub to test and build the image

REMOTE_USER="${REMOTE_USER:-deploy}"
REMOTE_HOST="${REMOTE_HOST:-169.58.188.122}"
REMOTE_DIR="${REMOTE_DIR:-/www/3inone}"
CONTAINER="${CONTAINER:-3inone_backend}"
CONTAINER_PORT="${CONTAINER_PORT:-8087}"   # the compose file publishes the container on 127.0.0.1:8087 of the server
LIVE_URL="${LIVE_URL:-https://3inone.nexoryatech.com}"
COMPOSE_FILE_LOCAL="docker-compose.prod.yml"   # becomes $REMOTE_DIR/docker-compose.yml on the server

BOLD="\033[1m"; BLUE="\033[1;34m"; GREEN="\033[1;32m"; YELLOW="\033[1;33m"; RED="\033[1;31m"; RESET="\033[0m"
STEP=0

# -- Helpers ------------------------------------------------------------------------------------------------------
step() { STEP=$((STEP + 1)); echo -e "\n${BLUE}[${STEP}]${RESET} ${BOLD}$*${RESET}"; }
ok()   { echo -e "${GREEN}    ✓ $*${RESET}"; }
warn() { echo -e "${YELLOW}    ⚠ $*${RESET}"; }
info() { echo -e "    $*"; }
err()  { echo -e "${RED}    ✗ $*${RESET}" >&2; exit 1; }

banner() {
  echo -e "\n${BOLD}╔══════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}║  3inone deploy  --  $1${RESET}"
  echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
}

elapsed() { local d=$((SECONDS - START)); printf "%dm %02ds" $((d / 60)) $((d % 60)); }

# ssh uses your usual key/agent/config unless SSH_KEY is set. A host key it has not seen is remembered, a changed
# one is refused (the old script switched host-key checking off, which hides a man in the middle).
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o BatchMode=yes)
if [ -n "${SSH_KEY:-}" ]; then SSH_OPTS+=(-i "$SSH_KEY"); fi
ssh_run() { ssh "${SSH_OPTS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" "$@"; }

need() { command -v "$1" >/dev/null 2>&1 || err "$1 not found - $2"; }

# -- Pre-flight ---------------------------------------------------------------------------------------------------
check_remote() {
  step "Pre-flight: server"
  need ssh "install OpenSSH"
  need curl "install curl"
  ssh_run "echo ok" >/dev/null 2>&1 || err "Cannot reach ${REMOTE_USER}@${REMOTE_HOST} over SSH (key? set SSH_KEY=/path/to/key)"
  ok "SSH to $REMOTE_HOST"

  # The stack must be the 3inone one. This stops a wrong REMOTE_DIR (say /www/depot) from being "deployed" to.
  ssh_run "test -f '$REMOTE_DIR/docker-compose.yml' && test -f '$REMOTE_DIR/.env' && grep -q '3inone-backend' '$REMOTE_DIR/docker-compose.yml'" \
    || err "$REMOTE_DIR on the server is not the 3inone stack (docker-compose.yml / .env missing, or it does not use $IMAGE_REPO)"
  ok "$REMOTE_DIR holds the 3inone stack"
}

# -- Git (release) ------------------------------------------------------------------------------------------------
git_push() {
  local msg="$1" url branch before head
  step "Git: commit the backend and push to $GIT_REMOTE/$GIT_BRANCH"
  need git "install git"

  url="$(git remote get-url "$GIT_REMOTE" 2>/dev/null)" || err "git remote '$GIT_REMOTE' does not exist (git remote add $GIT_REMOTE https://github.com/samwelmagaiwa/3inone.git)"
  case "$url" in
    */3inone|*/3inone.git) ;;
    *) err "remote '$GIT_REMOTE' is $url - the image is only built for the 3inone repository" ;;
  esac
  branch="$(git rev-parse --abbrev-ref HEAD)"
  [ "$branch" = "$GIT_BRANCH" ] || err "you are on '$branch'; releases are made from '$GIT_BRANCH'"

  # Only this folder (the backend) is committed. The app and anything else with changes is left as it is.
  git add -A -- .
  if git diff --cached --quiet; then
    warn "no backend changes to commit"
  else
    git commit -m "${msg}

Co-Authored-By: Samwel Magaiwa <samwelmagaiwa229@gmail.com>"
    ok "Committed: $msg"
  fi
  if [ -n "$(git status --porcelain)" ]; then
    warn "other changes outside the backend are NOT part of this release:"
    git status --short | sed 's/^/        /'
  fi

  git fetch --quiet "$GIT_REMOTE" "$GIT_BRANCH"
  before="$(git rev-parse "$GIT_REMOTE/$GIT_BRANCH")"
  git push "$GIT_REMOTE" "$GIT_BRANCH"        # never forced: a rejected push stops the release
  head="$(git rev-parse HEAD)"
  ok "Pushed to $GIT_REMOTE/$GIT_BRANCH ($(git rev-parse --short HEAD))"

  # GitHub only builds an image when the push touched the backend or the workflow itself.
  if [ -n "$(git diff --name-only "$before" "$head" -- ":(top)backend_mapato" ":(top)$CI_WORKFLOW_FILE")" ]; then
    BUILD_SHA="$head"
  else
    BUILD_SHA=""
  fi
  GITHUB_SLUG="$(printf '%s' "$url" | sed -E 's#^.*github\.com[:/]##; s#\.git$##')"
}

wait_for_image() {
  step "Docker Hub: wait for GitHub to test and build the image"
  if [ -z "${BUILD_SHA:-}" ]; then
    ok "this push changed no backend file, so no new image is built - rolling out the current $IMAGE"
    return
  fi
  need curl "install curl"
  info "commit ${BUILD_SHA:0:7}   progress: https://github.com/$GITHUB_SLUG/actions"
  local url="https://hub.docker.com/v2/repositories/$IMAGE_REPO/tags/$BUILD_SHA" waited=0 code
  while :; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$url" || true)"
    if [ "$code" = "200" ]; then ok "image $IMAGE_REPO:${BUILD_SHA:0:7} is on Docker Hub (tests passed)"; return; fi
    if [ "$waited" -ge "$CI_WAIT_SECONDS" ]; then
      err "no image for ${BUILD_SHA:0:7} after ${CI_WAIT_SECONDS}s - the tests probably failed: https://github.com/$GITHUB_SLUG/actions. Nothing was deployed. Once fixed run ./deploy.sh release again."
    fi
    printf "    waiting... %ss\r" "$waited"
    sleep 15; waited=$((waited + 15))
  done
}

# -- Local build (deploy) -----------------------------------------------------------------------------------------
build_and_push_image() {
  step "Docker: build the image here and push it (the GitHub tests are NOT run)"
  need docker "install Docker Desktop"
  docker info >/dev/null 2>&1 || err "the Docker daemon is not running - start Docker Desktop"
  local short tag
  short="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  tag="$IMAGE_REPO:local-$(date '+%Y%m%d%H%M')-$short"
  [ -z "$(git status --porcelain -- . 2>/dev/null)" ] || warn "the backend has uncommitted changes; they are part of this image"

  # linux/amd64 = what the server runs, whatever machine this is built on.
  docker build --platform linux/amd64 \
    --label "build.date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" --label "build.git=$short" \
    -t "$IMAGE" -t "$tag" . || err "docker build failed"
  ok "built $IMAGE and $tag"
  docker push "$tag"   || err "docker push failed - are you logged in? (docker login)"
  docker push "$IMAGE" || err "docker push failed - are you logged in? (docker login)"
  ok "pushed (roll back to this build with image: $tag in the compose file)"
}

# -- Roll out on the server ---------------------------------------------------------------------------------------
sync_compose() {
  local tmp
  tmp="$(mktemp)"
  ssh_run "cat '$REMOTE_DIR/docker-compose.yml'" > "$tmp"
  if diff -q "$tmp" "$COMPOSE_FILE_LOCAL" >/dev/null; then
    ok "docker-compose.yml on the server is up to date"
  else
    warn "docker-compose.yml on the server differs from $COMPOSE_FILE_LOCAL - updating it (old copy kept as docker-compose.yml.bak)"
    diff -u "$tmp" "$COMPOSE_FILE_LOCAL" | sed 's/^/        /' || true
    ssh_run "cp '$REMOTE_DIR/docker-compose.yml' '$REMOTE_DIR/docker-compose.yml.bak' && cat > '$REMOTE_DIR/docker-compose.yml.new' && mv '$REMOTE_DIR/docker-compose.yml.new' '$REMOTE_DIR/docker-compose.yml'" < "$COMPOSE_FILE_LOCAL" \
      || err "could not update docker-compose.yml on the server"
    ok "docker-compose.yml updated"
  fi
  rm -f "$tmp"
}

# Waits until the container answers; on failure prints its log and says how to go back.
wait_healthy() {
  local body
  for _ in $(seq 1 30); do
    body="$(ssh_run "curl -s --max-time 5 http://127.0.0.1:$CONTAINER_PORT/api/health" 2>/dev/null || true)"
    if printf '%s' "$body" | grep -q '"status":"success"'; then ok "$CONTAINER answers /api/health"; return 0; fi
    sleep 2
  done
  echo -e "${RED}    ✗ $CONTAINER did not answer /api/health within 60s. Last log lines:${RESET}" >&2
  ssh_run "docker logs --tail 25 '$CONTAINER' 2>&1" | sed 's/^/        /' >&2 || true
  err "Nothing is migrated. To go back to the previous build, set image: $IMAGE_REPO:<an earlier sha> in $REMOTE_DIR/docker-compose.yml and run docker compose up -d."
}

rollout() {
  step "Server: pull the new image and restart"
  sync_compose

  local before after
  before="$(ssh_run "docker inspect -f '{{.Image}}' '$CONTAINER' 2>/dev/null | cut -c8-19" || true)"

  # Docker Hub occasionally fails a blob read mid-pull; retry with a pause instead of failing the whole deploy.
  ssh_run "cd '$REMOTE_DIR' && for attempt in 1 2 3 4 5; do docker compose pull && break; [ \"\$attempt\" = 5 ] && exit 1; echo \"pull attempt \$attempt failed, retrying...\"; sleep \$((attempt * 5)); done" \
    || err "docker compose pull failed on the server after 5 attempts"
  ok "image pulled"
  ssh_run "cd '$REMOTE_DIR' && docker compose up -d --remove-orphans" || err "docker compose up failed on the server"
  after="$(ssh_run "docker inspect -f '{{.Image}}' '$CONTAINER' | cut -c8-19")"
  if [ "$before" = "$after" ]; then ok "container already ran this image ($after) - nothing to restart"
  else ok "container now runs image $after (was ${before:-none})"; fi
  wait_healthy
}

# A dump before anything touches the schema. Aborts (before any change) unless the dump is verified.
backup_database() {
  step "Database: back up before changing it"
  ssh_run "bash -s" -- "$REMOTE_DIR" <<'REMOTE' || err "backup failed - nothing was changed"
set -eu
cd "$1"
umask 077; mkdir -p backups
val() { grep -E "^$1=" .env | head -1 | cut -d= -f2- || true; }
DBN="$(val DB_DATABASE)"; DBN="${DBN:-3inone}"
DBU="$(val DB_USERNAME)"; DBU="${DBU:-3inone}"
DBH="$(val DB_HOST)";     DBH="${DBH:-127.0.0.1}"; [ "$DBH" = "host.docker.internal" ] && DBH=127.0.0.1
PW="$(val DB_PASSWORD)"
OUT="$PWD/backups/${DBN}_$(date +%Y%m%d_%H%M%S).sql"
docker run --rm --network host -e MYSQL_PWD="$PW" mysql:8.0 \
  mysqldump -h "$DBH" -u"$DBU" --single-transaction --routines --triggers --no-tablespaces --column-statistics=0 "$DBN" > "$OUT" 2> backups/.dump_errors || true
BYTES=$(wc -c < "$OUT")
if tail -3 "$OUT" | grep -q 'Dump completed' && [ "$BYTES" -gt 10000 ]; then
  echo "backup OK: $OUT ($BYTES bytes, $(grep -c '^CREATE TABLE' "$OUT") tables)"
else
  grep -v 'Using a password' backups/.dump_errors | head -3 >&2 || true
  rm -f "$OUT"; rm -f backups/.dump_errors
  echo "the dump did not complete (size $BYTES)" >&2; exit 1
fi
rm -f backups/.dump_errors
REMOTE
}

# How many migrations are waiting: prints a number, or stops if the answer cannot be read.
pending_migrations() {
  local out
  out="$(ssh_run "docker exec '$CONTAINER' php artisan migrate:status --pending 2>&1" || true)"
  if printf '%s' "$out" | grep -qi 'no pending migrations'; then echo 0
  elif printf '%s' "$out" | grep -q 'Pending'; then printf '%s\n' "$out" | grep -c 'Pending'
  else echo "could not read the migration status:" >&2; printf '%s\n' "$out" | head -5 | sed 's/^/        /' >&2; return 1; fi
}

run_migrations() {
  step "Laravel: migrations"
  local n
  n="$(pending_migrations)" || err "cannot tell whether migrations are pending - nothing was changed"
  if [ "$n" = "0" ]; then ok "no pending migrations"; return; fi
  if [ "${SKIP_MIGRATE:-0}" = "1" ]; then warn "$n pending migration(s) left alone (SKIP_MIGRATE=1) - run ./deploy.sh migrate when ready"; return; fi
  info "$n pending migration(s)"
  backup_database
  ssh_run "docker exec '$CONTAINER' php artisan migrate --force" \
    || err "migration failed. The database was backed up first (see the backup line above); Laravel runs each migration in its own step, so check 'migrate:status' before retrying."
  ok "migrations applied"
}

# The config cache is the one that matters: the container gets its settings from the environment, and with a cached
# config nothing reads .env again (this project only calls env() inside config/ and one seeder, so that is safe).
# The route cache is a speed-up and the routes here include closures (health, status page), which Laravel can
# serialize today; if a future route cannot be cached, that is a warning, not a failed deploy.
refresh_caches() {
  step "Laravel: caches"
  ssh_run "docker exec '$CONTAINER' php artisan config:cache && docker exec '$CONTAINER' php artisan view:clear" \
    || err "config cache failed (php artisan config:clear undoes it)"
  ok "config cached, views cleared"
  if ssh_run "docker exec '$CONTAINER' php artisan route:cache" >/dev/null 2>&1; then ok "routes cached"
  else
    ssh_run "docker exec '$CONTAINER' php artisan route:clear" >/dev/null 2>&1 || true
    warn "routes could not be cached (a route closure that cannot be serialized?) - running uncached, which is fine"
  fi
  wait_healthy
}

public_check() {
  step "Public address"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$LIVE_URL/api/health" 2>/dev/null || echo 000)"
  if [ "$code" = "200" ]; then ok "$LIVE_URL/api/health answers 200"
  else warn "$LIVE_URL/api/health answered HTTP $code - the container is healthy, so look at the reverse proxy / SSL in the panel"; fi
}

finish() {
  echo -e "\n${GREEN}${BOLD}✓ $1 complete in $(elapsed)${RESET}"
  echo -e "${GREEN}${BOLD}  Live -> $LIVE_URL${RESET}\n"
}

show_status() {
  step "Server status (read-only)"
  ssh_run "docker ps --filter name='$CONTAINER' --format '{{.Names}}  {{.Status}}  {{.Image}}'; echo \"image id: \$(docker inspect -f '{{.Image}}' '$CONTAINER' | cut -c8-19)\"; echo \"backups:  \$(ls '$REMOTE_DIR/backups' 2>/dev/null | grep -c '\.sql\$' || true) dump file(s)\"" | sed 's/^/    /'
  local n; n="$(pending_migrations)" && info "pending migrations: $n"
  wait_healthy
}

# -- Commands -----------------------------------------------------------------------------------------------------
CMD="${1:-help}"
MSG="${2:-Release $(date '+%Y-%m-%d %H:%M')}"
START=$SECONDS
BUILD_SHA=""; GITHUB_SLUG=""

case "$CMD" in
  release)
    banner "RELEASE"
    check_remote
    git_push "$MSG"
    wait_for_image
    rollout; run_migrations; refresh_caches; public_check
    finish "Release"
    ;;
  update)
    banner "UPDATE (current image)"
    check_remote
    rollout; run_migrations; refresh_caches; public_check
    finish "Update"
    ;;
  deploy)
    banner "DEPLOY (built here)"
    check_remote
    build_and_push_image
    rollout; run_migrations; refresh_caches; public_check
    finish "Deploy"
    ;;
  migrate)
    banner "MIGRATE"
    check_remote
    run_migrations
    finish "Migrate"
    ;;
  backup)
    banner "BACKUP"
    check_remote
    backup_database
    finish "Backup"
    ;;
  status)
    banner "STATUS"
    check_remote
    show_status
    ;;
  *)
    echo -e "\n${BOLD}Usage:${RESET}"
    echo "  ./deploy.sh release [\"message\"]  commit backend + push to GitHub, wait for the tested image, roll it out"
    echo "  ./deploy.sh update              roll out the image on Docker Hub now (pull, restart, migrate, caches)"
    echo "  ./deploy.sh deploy              build here + push + roll out (skips the GitHub tests)"
    echo "  ./deploy.sh migrate             back up the database, then run pending migrations"
    echo "  ./deploy.sh backup              database dump on the server only"
    echo "  ./deploy.sh status              read-only look at the server"
    echo ""
    echo -e "${BOLD}Environment:${RESET}"
    echo "  SSH_KEY=/path/to/key   use this key         SKIP_MIGRATE=1   roll out but leave migrations pending"
    echo "  CI_WAIT_SECONDS=1500   how long release waits for GitHub"
    echo ""
    exit 1
    ;;
esac
