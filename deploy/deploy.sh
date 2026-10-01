#!/bin/sh
# `pnpm deploy:server` — deploys the server by hand, from this Mac (deploy/README.md). What goes
# live is origin/main, not this working tree: merge first. Override the box with FUSE_HOST and
# the key with FUSE_SSH_KEY.
set -eu
cd "$(dirname "$0")/.."
HOST="${FUSE_HOST:-ubuntu@13.236.155.188}"
KEY="${FUSE_SSH_KEY:-$HOME/.ssh/fuseos.pem}"
ssh_box() { ssh -i "$KEY" -o ConnectTimeout=10 "$HOST" "$@"; }

[ -f deploy/server.env ] || { echo "deploy/server.env is missing (the production settings)" >&2; exit 1; }
PROD_DB=$(grep '^DATABASE_URL=' deploy/server.env | cut -d= -f2- | tr -d '"')
[ -n "$PROD_DB" ] || { echo "DATABASE_URL is empty in deploy/server.env" >&2; exit 1; }

echo "1/4  migrating the production database"
DATABASE_URL="$PROD_DB" pnpm -s db:migrate

echo "2/4  copying the production settings"
scp -q -i "$KEY" deploy/server.env "$HOST:FuseOS/deploy/server.env"
ssh_box 'chmod 600 FuseOS/deploy/server.env'

echo "3/4  pulling main and rebuilding (a few minutes on the small box)"
ssh_box 'set -e; cd FuseOS && git fetch -q origin && git checkout -q main && git reset -q --hard origin/main && git log --oneline -1 && cd deploy && sudo docker compose up -d --build --quiet-pull 2>&1 | grep -E "Started|Running|Recreated|error" || true; sudo docker image prune -f >/dev/null'

echo "4/4  waiting for /health"
for _ in $(seq 1 30); do
  if curl -fsS https://fuseos-api.theshaik.dev/health; then echo "  live"; exit 0; fi
  sleep 5
done
echo "the server did not come back healthy: ssh in and run 'cd FuseOS/deploy && sudo docker compose logs server'" >&2
exit 1
