#!/bin/sh
# The server's deploy, run by .github/workflows/deploy.yml over SSH. Installed on the box as
# /usr/local/bin/fuseos-deploy and pinned to the deploy key in ~/.ssh/authorized_keys
# (command="..."), so that key can run this and nothing else. The commit to deploy arrives as
# the SSH command. Reinstall after editing (deploy/README.md).
set -eu
sha="${SSH_ORIGINAL_COMMAND:-${1:-}}"
case "$sha" in
  '' | *[!0-9a-f]*) echo "usage: fuseos-deploy <commit sha>" >&2; exit 2 ;;
esac
cd "$HOME/FuseOS"
before=$(git rev-parse HEAD)
git fetch -q origin main
git checkout -q --detach "$sha"
# Only what goes into the server image: a website-only merge rebuilds nothing.
if [ "$before" != "$sha" ] && git diff --quiet "$before" "$sha" -- server packages deploy pnpm-lock.yaml package.json pnpm-workspace.yaml; then
  echo "no server changes since ${before}: nothing to rebuild"
  exit 0
fi
cd deploy
sudo docker compose up -d --build
sudo docker image prune -f >/dev/null
echo "deployed $sha"
