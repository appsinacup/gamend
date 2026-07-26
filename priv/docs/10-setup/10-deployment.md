---
icon: hero-cloud-arrow-up
---

# Deployment

Deploy your own game server instance using the starter repository. The quickest path is Docker Compose — clone, configure, and run. If you want a full Elixir host app that you can edit directly, see the Elixir App Starter guide below.

Two supported starting paths

- Docker starter: fastest path to running a server with minimal code changes
- Elixir app starter: best path when you want to own the host app, routes, branding, and runtime policy in code

## What each project owns

The repository is split by responsibility. Treat host as the runtime shell you customize, and core/web as reusable packages that you update from upstream.

| Project | Owns | Typical changes |
|---|---|---|
| game_server_core | Shared domain logic, Ecto schemas, contexts, and upstream migrations | New shared features, shared data model changes, reusable business rules |
| game_server_web | Shared controllers, LiveViews, channels, components, and shared frontend source | Reusable API/UI behavior that multiple hosts should inherit |
| game_server_host | The runnable app: router, endpoint boot, supervision tree, env/config, branding, docs, startup scripts, and host-only migrations | Routes you add or remove, deployment policy, assets, host-owned pages, integrations, and data that only your host needs |

## Host-only migrations

Put upstream shared schema changes in game_server_core, but put host-specific tables or columns in priv/repo/migrations at the repository root. The host migration command runs both core and host paths together.

```bash
mix ecto.gen.migration add_custom_host_table

mix ecto.migrate
```

Migration versions from core and host are sorted together, so give host migrations a normal timestamp and keep host-only schema/modules in the host project unless you intentionally want to upstream them into core.

## Clone the Docker starter repository

The starter repo contains a pre-configured Docker Compose setup with the game server, PostgreSQL, and optional Redis for caching.

```bash
git clone https://github.com/appsinacup/gamend_starter.git
cd gamend_starter
```

## Configure environment variables

Copy the example environment file and edit it to set your secrets and configuration.

```bash
cp .env.example .env
```

Key variables to set:

| Variable | Description |
|---|---|
| GAMEND_AUTH_SECRET_KEY_BASE | 64-byte hex secret for session signing. Generate with: mix phx.gen.secret |
| GAMEND_DB_URL | PostgreSQL connection string (pre-configured for the Docker Compose DB) |
| GAMEND_HTTP_HOST | Your public hostname (e.g. play.example.com) |
| GAMEND_AUTH_GUARDIAN_SECRET_KEY | Secret for signing JWT API tokens |

See the .env.example file for the full list of available environment variables including OAuth providers, email, rate limiting, and more.

## Start the server

Start everything with Docker Compose:

```bash
docker compose up -d
```

The server will be available at http://localhost:4000 by default. Database migrations run automatically on startup.

## Verify the deployment

Check that the server is running:

```bash
curl http://localhost:4000/api/v1/health

docker compose logs -f app
```

## Production recommendations

- Enable HTTPS with automatic certificate renewal (see below)
- Set GAMEND_HTTP_HOST to your actual domain
- Configure OAuth providers for social login (see provider guides above)
- Enable email delivery via SMTP for password resets and notifications
- Set up Redis for distributed caching when running multiple instances (see Scaling guide)
- Review rate limiting settings for your expected traffic

## Data retention

A sweep runs every 6 hours and prunes tables that would otherwise grow forever.
Each class has its own window; `0` keeps that class forever. The current values
and their variables are in the [Settings](/docs/setup?guide=settings) guide
under **Retention**; the last run and its per-class counts are on
Admin -> System, which can also sweep on demand.

Two rules worth knowing before you tune them:

- A lobby is deleted only when **nobody in it has been seen** for the window, so
  a reconnect always saves one. Ending a match is not itself a reason to delete:
  a game that ends one deletes its own lobby.
- Expired sessions and magic-link tokens are always pruned on their own
  validity and are not configurable.

## HTTPS

Gamend terminates TLS itself through Bandit — no nginx or reverse proxy. Point
it at a certificate and it serves HTTPS on 443, keeping HTTP on 4000 for ACME
challenges. Erlang's `:ssl` re-reads the files from disk, so a renewal takes
effect **without a restart**.

| Variable | Purpose |
|---|---|
| `GAMEND_TLS_CERTFILE` | Path to `fullchain.pem` (certificate + CA chain) |
| `GAMEND_TLS_KEYFILE` | Path to `privkey.pem` |
| `GAMEND_TLS_FORCE` | `true` redirects HTTP to HTTPS and enables HSTS |
| `GAMEND_TLS_ACME_WEBROOT` | Directory the ACME challenge is served from |

Get a certificate with the server already running on HTTP, so certbot can
validate over the webroot:

```bash
sudo mkdir -p /var/www/acme
sudo certbot certonly --webroot --webroot-path /var/www/acme \
  --email admin@example.com --agree-tos --no-eff-email -d play.example.com
```

Then point the server at what certbot wrote and restart:

```bash
GAMEND_HTTP_HOST=play.example.com
GAMEND_TLS_CERTFILE=/etc/letsencrypt/live/play.example.com/fullchain.pem
GAMEND_TLS_KEYFILE=/etc/letsencrypt/live/play.example.com/privkey.pem
GAMEND_TLS_FORCE=true
GAMEND_TLS_ACME_WEBROOT=/var/www/acme
```

Certbot installs its own renewal timer, so there is nothing further to
schedule; `sudo certbot renew --dry-run` confirms it works.

### Docker setup

When running in Docker, mount the certificate directory and ACME challenge directory as volumes. Add these to your docker-compose.yml:

```yaml
# docker-compose.yml — add HTTPS support
services:
  app:
    ports:
      - "4000:4000"
      - "443:443"
    environment:
      GAMEND_HTTP_HOST: play.example.com
      GAMEND_TLS_CERTFILE: /etc/letsencrypt/live/play.example.com/fullchain.pem
      GAMEND_TLS_KEYFILE: /etc/letsencrypt/live/play.example.com/privkey.pem
      GAMEND_TLS_FORCE: "true"
      GAMEND_TLS_ACME_WEBROOT: /var/www/acme
    volumes:
      - ./certbot/conf:/etc/letsencrypt:ro
      - ./certbot/www:/var/www/acme:ro
```

Run certbot on the host machine (not inside Docker). It writes to ./certbot/conf/ and ./certbot/www/ which are mounted into the container:

```bash
# 1. Create cert directories
mkdir -p certbot/conf certbot/www

# 2. Start the server (HTTP only — certs don't exist yet)
docker compose up -d

# 3. Get your first certificate (run on the HOST)
sudo certbot certonly \
  --webroot --webroot-path ./certbot/www \
  --email admin@example.com --agree-tos \
  -d play.example.com \
  --config-dir ./certbot/conf \
  --work-dir ./certbot/work \
  --logs-dir ./certbot/logs

# 4. Restart to enable HTTPS (cert files now exist)
docker compose up -d

# 5. Set up auto-renewal cron on the host (every 12 hours)
(crontab -l 2>/dev/null; echo "0 */12 * * * certbot renew --config-dir $(pwd)/certbot/conf --work-dir $(pwd)/certbot/work --logs-dir $(pwd)/certbot/logs --quiet") | crontab -
```

Renewed certs are picked up automatically — no container restart needed.

### Environment variables reference

| Variable | Description | Default |
|---|---|---|
| GAMEND_TLS_CERTFILE | Path to fullchain.pem (certificate + CA chain) | — |
| GAMEND_TLS_KEYFILE | Path to privkey.pem | — |
| GAMEND_TLS_PORT | Port for HTTPS listener | 443 |
| GAMEND_TLS_FORCE | Redirect HTTP → HTTPS and enable HSTS | true when GAMEND_TLS_CERTFILE is set |
| GAMEND_TLS_ACME_WEBROOT | Webroot directory for Let's Encrypt HTTP-01 challenges (same as certbot --webroot-path) | /var/www/acme |

Port 443 access

Binding to port 443 requires root access or Linux capabilities. In Docker this works by default. On bare metal, use: sudo setcap 'cap_net_bind_service=+ep' $(which beam.smp) — or use iptables to redirect port 443 to a higher port.
