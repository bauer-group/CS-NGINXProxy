# NGINX Proxy Manager Server Image

Published as `ghcr.io/bauer-group/cs-nginxproxy/nginx-proxy-manager`.
A thin, professional wrapper around the official
[`jc21/nginx-proxy-manager`](https://hub.docker.com/r/jc21/nginx-proxy-manager)
image — tracking the floating **`2`** tag (latest NPM 2.x; major pinned to avoid
a breaking jump to 3.x).

It keeps the upstream image fully intact and only layers on packaging concerns:

| Concern | Upstream image | This image |
| --- | --- | --- |
| Identity / supply chain | generic public image | OCI labels, own GHCR image, SBOM, scans, base-image monitor |
| HTTP/3 (QUIC) | compiled in, but not wired into the config | activated by default (per-host `quic` listeners + `Alt-Svc`) |
| Boot visibility | silent | branded banner echoing the effective runtime config |

## Why no nginx rebuild is needed

The upstream image already ships an OpenResty build with QUIC support compiled
in — verified straight from the image:

```text
nginx version: openresty/1.29.2.5
built with OpenSSL 3.5.x
configure arguments: ... --with-http_v2_module --with-http_v3_module --with-stream ...
```

So HTTP/3 is purely a **configuration** concern, not a build concern. This image
wires it in instead of forking and recompiling nginx. See
[`docs/http3-and-quic.md`](../../docs/http3-and-quic.md) for the full mechanism.

## What it does NOT change

The upstream runtime contract is preserved verbatim:

| Property | Value |
| --- | --- |
| Data dir | `/data` (database, certs metadata, generated nginx configs) |
| Certs dir | `/etc/letsencrypt` |
| Database | embedded **SQLite** at `/data/database.sqlite` (no external DB) |
| Ports | `80` (HTTP), `443` (HTTPS, TCP+UDP), `81` (admin UI) |
| Healthcheck | `/usr/bin/check-health` (bundled, hits the local admin API) |
| PID 1 | `/init` (s6-overlay; signal handling unchanged) |

## Entrypoint chain

```text
/usr/local/bin/docker-entrypoint-custom.sh /init
  ├── prints the boot banner
  ├── runs http3-enable.sh  (wires QUIC into default.conf + _listen.conf)
  └── exec /init            (s6-overlay becomes PID 1)
```

`http3-enable.sh` runs **before** `/init` so that when NPM's s6 services
regenerate the nginx configs they already see the patched listen template. It
works against `.orig` snapshots taken at build time, so the activation is
idempotent and a single env toggle (`NPM_HTTP3_ENABLE=false`) fully reverts it.

## Build

```bash
docker build \
  --build-arg NPM_VERSION=2 \
  -t ghcr.io/bauer-group/cs-nginxproxy/nginx-proxy-manager:local .
```

## Environment

| Variable | Default | Purpose |
| --- | --- | --- |
| `NPM_HTTP3_ENABLE` | `true` | wire HTTP/3 (QUIC) into the nginx config |
| `DISABLE_IPV6` | `false` | comment out `listen [::]` lines (upstream behaviour) |
| `DB_SQLITE_FILE` | `/data/database.sqlite` | embedded SQLite database path |
| `INITIAL_ADMIN_EMAIL` | _(unset)_ | optional: provision the admin instead of the first-run setup wizard |
| `INITIAL_ADMIN_PASSWORD` | _(unset)_ | optional: password for the provisioned admin (secret) |
| `TZ` | `Etc/UTC` | container timezone |

See the repository root `README.md` and `docs/` for full deployment guidance.
