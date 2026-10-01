# Hosting the control plane

The server is small: sign-in, the device list, and the `/signal` WebSocket. Clipboard and
file payloads never reach it (they go device to device), so one small box is enough.

- **Database:** Neon Postgres (free tier), unchanged.
- **Server:** this repo's `server/Dockerfile`, behind Caddy for HTTPS, via `deploy/compose.yaml`.
- **Where:** AWS Lightsail or EC2 while the credits last (about $5–8 a month). When the credits end,
  Oracle Cloud Always Free or Google Cloud's free e2-micro run the same two commands.

## Continuous deployment

Every merge to `main` deploys itself once CI passes (`.github/workflows/deploy.yml`): it migrates
the production database (`PROD_DATABASE_URL`), then SSHes to the box with a deploy key that can
only run `deploy/deploy.sh` (installed as `/usr/local/bin/fuseos-deploy`, pinned with
`command="..."` in `~/.ssh/authorized_keys`), which checks out that commit and rebuilds only if
server code changed, and finally waits for `/health`. Run it by hand from **Actions → Deploy
server → Run workflow**.

- The security group's SSH rule must allow GitHub's runners (**Anywhere**): password logins are
  off, and the only keys are yours and the forced-command deploy key.
- After editing `deploy/deploy.sh`, reinstall it on the box:
  `scp deploy/deploy.sh ubuntu@<ip>:/tmp/d && ssh ubuntu@<ip> 'sudo install -m 755 /tmp/d /usr/local/bin/fuseos-deploy'`.
- Repo settings it needs: secrets `DEPLOY_SSH_KEY`, `PROD_DATABASE_URL`; variables `DEPLOY_HOST`,
  `DEPLOY_KNOWN_HOSTS` (the box's host key, so another machine at that address is refused).

## 1. A box and a name

1. Create an Ubuntu 24.04 instance (1 GB RAM is plenty). Open ports **80** and **443**.
2. Give it a static IP (Lightsail: *Networking → Attach static IP*).
3. Point a hostname at that IP: your own domain's A record, or a free
   [DuckDNS](https://www.duckdns.org) name such as `fuseos.duckdns.org`.

## 2. Run it

On the box:

```sh
curl -fsSL https://get.docker.com | sh
git clone https://github.com/mrstrange1708/FuseOS.git && cd FuseOS/deploy
cp server.env.example server.env    # fill in DATABASE_URL and BETTER_AUTH_SECRET
FUSE_DOMAIN=fuseos.duckdns.org docker compose up -d --build
curl https://fuseos.duckdns.org/health   # {"status":"ok"}
```

Caddy fetches and renews the certificate itself. To update the server later:
`git pull && FUSE_DOMAIN=… docker compose up -d --build`.

## 3. Point the apps at it

In the repo settings, set the variable **`FUSE_SERVER_URL`** to `https://fuseos.duckdns.org`.
Then push a tag, and `.github/workflows/release.yml` builds and publishes the APK and DMG
pointed at it:

```sh
git tag v0.2.0 && git push origin v0.2.0
```

Dev builds keep using your Mac (`localhost` / its LAN IP); only release builds use the hosted URL.
