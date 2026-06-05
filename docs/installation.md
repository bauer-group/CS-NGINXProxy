# Installation

## Prerequisites

- Docker Engine 24+ with the Compose v2 plugin (`docker compose`)
- The host ports you intend to publish must be free — by default **80/tcp**,
  **443/tcp**, **443/udp** and **8080/tcp** (admin UI)
- DNS records for the domains you will proxy, pointing at this host (required for
  Let's Encrypt HTTP-01 challenges)
- Firewall: inbound **TCP/80**, **TCP/443** and — for HTTP/3 — **UDP/443**

## 1. Configure environment

There are **no secrets to generate** — NPM ships a default admin account that you
change on first login. Just copy the example and review it:

```bash
cp .env.example .env            # Linux/macOS
Copy-Item .env.example .env     # Windows PowerShell
```

Edit `.env`:

- `STACK_NAME` — name prefix for the container and volumes
- `TIME_ZONE` — e.g. `Europe/Berlin`
- `PORT_HTTP` / `PORT_HTTPS` / `PORT_ADMIN` — host port mapping
- `DISABLE_IPV6=true` — only if your host has no IPv6
- `NPM_HTTP3_ENABLE` — leave `true` for HTTP/3 (see
  [http3-and-quic.md](http3-and-quic.md))

## 2. Start

```bash
# Production — pre-built GHCR image
docker compose -f docker-compose.production.yml up -d

# Development — local image build
docker compose -f docker-compose.development.yml up -d --build
```

## 3. First-run: create the admin account

Open the admin UI and complete the one-time **setup wizard**, which creates your
administrator account:

| URL | First run |
| --- | --- |
| `http://<host>:8080` (or your `PORT_ADMIN`) | setup wizard creates your admin account |

The account and all proxy hosts are stored in the embedded SQLite database in the
`npm-data` volume — there is no admin password in `.env` by design.

> **Automated deployments:** set `INITIAL_ADMIN_EMAIL` and
> `INITIAL_ADMIN_PASSWORD` in `.env` (and uncomment the matching lines in the
> compose file). On a fresh database NPM then creates that admin and skips the
> wizard. Treat these as secrets and rotate via the UI after first login.

## 4. Verify

```bash
# Container healthy? (look for "healthy" in STATUS)
docker compose -f docker-compose.production.yml ps

# Boot banner + effective config (HTTP/3 line, ports, DB path)
docker compose -f docker-compose.production.yml logs nginx-proxy-manager | head -n 40

# Admin API reachable?
curl -fsS http://localhost:8080/api/ | head

# nginx config valid inside the container? (should print "test is successful")
docker compose -f docker-compose.production.yml exec nginx-proxy-manager nginx -t
```

Once you have created a proxy host with a TLS certificate, confirm HTTP/3 is
advertised:

```bash
curl -sI --resolve your.domain:443:<host-ip> https://your.domain | grep -i alt-svc
# -> alt-svc: h3=":443"; ma=86400
```

## 5. Create your first proxy host

In the admin UI: **Hosts → Proxy Hosts → Add Proxy Host**

- **Domain Names** — `app.example.com`
- **Forward Hostname/IP & Port** — your backend (e.g. `10.0.0.5` : `8080`).
  It may be on another host; NPM connects out to it.
- **SSL tab** — request a new Let's Encrypt certificate, enable *Force SSL* and
  *HTTP/2 Support*. HTTP/3 is added automatically for every TLS host.

## Upgrading NPM

The data and letsencrypt volumes persist across restarts, so upgrades are
non-destructive:

```bash
# Production (GHCR): bump NGINX_PROXY_MANAGER_IMAGE_VERSION in .env, then
docker compose -f docker-compose.production.yml pull
docker compose -f docker-compose.production.yml up -d

# Development (local build): bump NPM_VERSION in .env, then
docker compose -f docker-compose.development.yml up -d --build
```

> **Back up first.** NPM runs database migrations on upgrade. Snapshot the
> `npm-data` volume before a major jump — see
> [backup-and-restore.md](backup-and-restore.md). Review the upstream
> [release notes](https://github.com/NginxProxyManager/nginx-proxy-manager/releases)
> before crossing major versions.

Base-image digest moves are picked up automatically by `check-base-images.yml`
(daily) and tag bumps by Dependabot, both of which trigger a fresh GHCR build.
