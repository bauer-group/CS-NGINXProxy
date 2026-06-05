# Backup & Restore

**Everything** Nginx Proxy Manager knows — proxy/redirection/stream hosts, access
lists, users, settings — lives in the embedded SQLite database under `/data`. The
issued TLS certificates and the ACME account live under `/etc/letsencrypt`. Back
up those two volumes and you have a complete, portable backup. Nothing of value
lives in the repo or `.env`.

## What's in the volumes

| Volume | Mount | Contents |
| --- | --- | --- |
| `${STACK_NAME}-data` | `/data` | SQLite database, generated nginx configs, custom snippets, logs |
| `${STACK_NAME}-letsencrypt` | `/etc/letsencrypt` | issued certificates, private keys, ACME account |

The named volumes resolve to `${STACK_NAME}-data` and `${STACK_NAME}-letsencrypt`
(e.g. `nginxproxy_example_domain_com-data`).

## Back up (cold — recommended)

A cold backup (container stopped) guarantees a consistent SQLite snapshot:

```bash
COMPOSE=docker-compose.production.yml
STACK=nginxproxy_example_domain_com   # your STACK_NAME

docker compose -f $COMPOSE stop nginx-proxy-manager

mkdir -p ./backup
# Database + configs
docker run --rm \
  -v ${STACK}-data:/data:ro \
  -v "$(pwd)/backup":/backup \
  alpine tar czf /backup/npm-data-$(date +%Y%m%d-%H%M%S).tar.gz -C /data .
# Certificates
docker run --rm \
  -v ${STACK}-letsencrypt:/le:ro \
  -v "$(pwd)/backup":/backup \
  alpine tar czf /backup/npm-letsencrypt-$(date +%Y%m%d-%H%M%S).tar.gz -C /le .

docker compose -f $COMPOSE start nginx-proxy-manager
```

## Back up (hot)

If you can't stop the service, a hot tar of `/data` usually works because SQLite
is journaled — but a cold backup is the only one guaranteed consistent. For
zero-downtime guarantees, snapshot at the storage layer (LVM / ZFS / cloud volume
snapshot) instead. Always back up **both** volumes together so certificates and
the database stay in sync.

## Restore

```bash
COMPOSE=docker-compose.production.yml
STACK=nginxproxy_example_domain_com

docker compose -f $COMPOSE down

docker volume create ${STACK}-data
docker volume create ${STACK}-letsencrypt

docker run --rm \
  -v ${STACK}-data:/data \
  -v "$(pwd)/backup":/backup \
  alpine sh -c "rm -rf /data/* && tar xzf /backup/<your-npm-data>.tar.gz -C /data"
docker run --rm \
  -v ${STACK}-letsencrypt:/le \
  -v "$(pwd)/backup":/backup \
  alpine sh -c "rm -rf /le/* && tar xzf /backup/<your-npm-letsencrypt>.tar.gz -C /le"

docker compose -f $COMPOSE up -d
```

## Migrating to another host

1. Cold-backup **both** volumes on the old host (above).
2. Copy the two `.tar.gz` files and your `.env` to the new host.
3. Restore the volumes, then `docker compose ... up -d`.
4. Re-point your DNS records at the new host.

All hosts, settings and certificates come back exactly as they were — there is no
separate credential to re-enter.

> **HTTP/3 on restored hosts:** proxy hosts created by a *stock* NPM before
> migrating may need a one-time re-save to pick up the QUIC listeners — see
> [http3-and-quic.md](http3-and-quic.md#caveat-existing-hosts-on-a-migrated-data-volume).

## Automate it

Schedule the cold-backup snippet (e.g. a nightly cron / systemd timer) and ship
the archives off-host. Keep a rolling window (e.g. 14 daily + 8 weekly) and
**test a restore periodically** — an untested backup is a hope, not a backup.
