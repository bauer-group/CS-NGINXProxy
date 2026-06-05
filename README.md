# NGINX Proxy Manager

Production-ready, self-hosted reverse proxy with a web UI, powered by
[Nginx Proxy Manager](https://github.com/NginxProxyManager/nginx-proxy-manager)
(NPM) **2**, packaged as a thin BAUER GROUP edition image with **turnkey HTTP/3
(QUIC)** and full CI/CD automation.

Tracks the floating `2` image tag — always the latest NPM 2.x, with the major
pinned to avoid a breaking jump to 3.x.

A thin, professional wrapper around the official `jc21/nginx-proxy-manager`
image: no forking, no nginx recompile. NPM runs as the **edge proxy directly on
the host** — it terminates TLS itself and forwards to your backends (which may
live on other hosts). It is built for special cases and small environments where
a Traefik stack is overkill and Kubernetes is not in play.

## Features

- **HTTP/1.1 + HTTP/2 + HTTP/3** — HTTP/3 (QUIC over UDP/443) is wired in by
  default by activating the QUIC support already compiled into the upstream
  nginx (OpenResty + OpenSSL 3.5). No nginx rebuild, no fork. See
  [docs/http3-and-quic.md](docs/http3-and-quic.md).
- **Embedded SQLite** — no external database. The whole proxy configuration and
  the user accounts live in a single SQLite file in the data volume.
- **Web UI for proxy hosts & TLS** — manage proxy/redirection/stream/404 hosts,
  request and auto-renew Let's Encrypt certificates, access lists, and custom
  nginx snippets — all from the admin UI.
- **No secrets to manage** — the admin account is created in a first-run setup
  wizard (or optionally provisioned via `INITIAL_ADMIN_*`); nothing in `.env` to
  rotate or leak by default.
- **Healthcheck built in** — the bundled `/usr/bin/check-health` probes the
  admin API; Docker restarts the container if it goes unhealthy.
- **CI/CD automation** — semantic releases, GHCR image builds, base-image
  monitoring, Dependabot auto-merge, SBOMs, Teams + AI issue triage.

## Quick Start

1. **Clone & enter**
   ```bash
   git clone https://github.com/bauer-group/CS-NGINXProxy.git
   cd CS-NGINXProxy
   ```

2. **Create `.env`** (no secrets to generate — just copy the template)
   ```bash
   cp .env.example .env            # Linux/macOS
   Copy-Item .env.example .env     # Windows PowerShell
   ```

3. **Review `.env`** — set `STACK_NAME`, `TIME_ZONE`, the host `PORT_*` values,
   and (if your host has no IPv6) `DISABLE_IPV6=true`.

4. **Start**
   ```bash
   # Production (pre-built GHCR image)
   docker compose -f docker-compose.production.yml up -d

   # Development (local image build)
   docker compose -f docker-compose.development.yml up -d --build
   ```

5. **Create the admin account** — open the admin UI and complete the first-run
   setup wizard:

   | URL | First run |
   | --- | --- |
   | `http://<host>:${PORT_ADMIN:-8080}` | setup wizard creates your admin account |

   To skip the wizard in automated deployments, set `INITIAL_ADMIN_EMAIL` and
   `INITIAL_ADMIN_PASSWORD` in `.env` (and uncomment them in the compose file).

6. **Open the firewall for HTTP/3** — allow inbound **UDP/443** in addition to
   TCP/80 and TCP/443, otherwise browsers silently stay on HTTP/2.

## Architecture

```
                         Internet
            TCP/80   TCP/443   UDP/443        :8080 (admin, plain HTTP)
              │        │         │               │
┌─────────────┼────────┼─────────┼───────────────┼─────────────────────┐
│             ▼        ▼         ▼               ▼      Docker host      │
│   ┌──────────────────────────────────────────────────────────────┐   │
│   │                  nginx-proxy-manager                          │   │
│   │                 (BAUER GROUP edition)                         │   │
│   │                                                               │   │
│   │   :80   HTTP                :81  Admin UI (web + API)          │   │
│   │   :443  HTTPS  H1/H2 (TCP) + H3/QUIC (UDP)                     │   │
│   │   Healthcheck  /usr/bin/check-health                          │   │
│   │   PID 1        s6-overlay (/init)                             │   │
│   │                                                               │   │
│   │   /data            ──► npm-data volume (SQLite DB + configs)   │   │
│   │   /etc/letsencrypt ──► npm-letsencrypt volume (certs)          │   │
│   └──────────────────────────────────────────────────────────────┘   │
│             │                │                 │                       │
└─────────────┼────────────────┼─────────────────┼──────────────────────┘
              ▼                ▼                 ▼
        backend A          backend B         backend C
       (same host)       (other host)      (other host)
```

## Deployment Modes

| Mode | Compose file | Image | Use for |
| --- | --- | --- | --- |
| **Production** | `docker-compose.production.yml` | pre-built GHCR | normal single-host edge deployment |
| **Development** | `docker-compose.development.yml` | local build | building & testing the edition image |

> There are no Traefik/Coolify modes here on purpose: **NPM is itself the edge
> proxy**, so it is not placed behind another one.

## Configuration

Everything is driven from `.env` — see [docs/configuration.md](docs/configuration.md)
for the full variable reference. Highlights:

- **Image** — `NGINX_PROXY_MANAGER_IMAGE` / `…_IMAGE_VERSION` (our GHCR image) or
  `NPM_REPOSITORY` / `NPM_VERSION` (upstream local build base).
- **HTTP/3** — `NPM_HTTP3_ENABLE` (default `true`).
- **Networking** — `PORT_HTTP`, `PORT_HTTPS`, `PORT_ADMIN`, `DISABLE_IPV6`.
- **Database** — `DB_SQLITE_FILE` (embedded SQLite; no external DB).

## Ports

| Container port | Host default | Purpose |
| --- | --- | --- |
| 80/tcp | 80 | Public HTTP |
| 443/tcp | 443 | Public HTTPS — HTTP/1.1 + HTTP/2 |
| 443/udp | 443 | Public HTTPS — HTTP/3 / QUIC |
| 81/tcp | 8080 | Admin web UI (plain HTTP) |

Extra TCP/UDP **stream** forwards configured in the UI need their ports
published in the compose file too — see [docs/configuration.md](docs/configuration.md#stream-ports).

## Documentation

- [Installation](docs/installation.md)
- [Configuration](docs/configuration.md)
- [HTTP/3 & QUIC](docs/http3-and-quic.md)
- [Backup & restore](docs/backup-and-restore.md)
- [Server image reference](src/nginx-proxy-manager/README.md)

## License

MIT License — BAUER GROUP. See [LICENSE](LICENSE).
