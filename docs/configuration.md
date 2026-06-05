# Configuration

This stack is driven from `.env`. NPM itself stores its runtime configuration
(proxy hosts, certificates, access lists, users) in an embedded SQLite database
inside the data volume — **not** in environment variables.

## Environment variables

| Variable | Default | Used by | Purpose |
| --- | --- | --- | --- |
| `STACK_NAME` | `nginxproxy_example_domain_com` | all | prefix for container/volume names |
| `TIME_ZONE` | `Etc/UTC` | all | container timezone (`TZ`) |
| `NGINX_PROXY_MANAGER_IMAGE` | `ghcr.io/bauer-group/cs-nginxproxy/nginx-proxy-manager` | production | our published image to pull |
| `NGINX_PROXY_MANAGER_IMAGE_VERSION` | `latest` | production | our published image tag |
| `NPM_REPOSITORY` | `jc21/nginx-proxy-manager` | development | upstream base image to build from |
| `NPM_VERSION` | `2` | development | upstream base tag (floating 2.x) |
| `NPM_HTTP3_ENABLE` | `true` | all | wire HTTP/3 (QUIC) into the nginx config |
| `DISABLE_IPV6` | `false` | all | comment out `listen [::]` lines |
| `DB_SQLITE_FILE` | `/data/database.sqlite` | all | embedded SQLite database path |
| `INITIAL_ADMIN_EMAIL` | _(unset)_ | all | optional: provision the admin instead of the setup wizard |
| `INITIAL_ADMIN_PASSWORD` | _(unset)_ | all | optional: password for the provisioned admin (secret) |
| `PORT_HTTP` | `80` | all | host port mapped to container `80` |
| `PORT_HTTPS` | `443` | all | host port mapped to container `443` (TCP + UDP) |
| `PORT_ADMIN` | `8080` | all | host port mapped to container `81` (admin UI) |

## Database — embedded SQLite (no external DB)

NPM uses SQLite by default; there is **no MySQL/MariaDB/Postgres to run**. The
database is a single file at `DB_SQLITE_FILE` (default `/data/database.sqlite`),
which lives in the `npm-data` volume. This is the recommended setup for the
single-host edge use case this stack targets — back up the volume and you have
backed up the entire configuration (see [backup-and-restore.md](backup-and-restore.md)).

You normally never need to change `DB_SQLITE_FILE`; it exists only so the path
can be relocated within the container if you have a specific reason to.

## Admin account

On first start, NPM shows a **setup wizard** in the web UI that creates the
administrator account. Because the account lives in the database (the data
volume), there is intentionally no admin password in `.env` by default — nothing
to rotate in the environment, nothing to leak.

For automated, non-interactive deployments you can provision the admin instead:

```env
INITIAL_ADMIN_EMAIL=admin@example.com
INITIAL_ADMIN_PASSWORD=<a strong password>
```

(also uncomment the matching lines in the compose file). When **both** are set,
NPM creates that admin once on a fresh database and skips the wizard. These are
credentials — keep them out of version control, and rotate via the UI after the
first login. If either is empty, the wizard is used.

## The admin UI is plain HTTP

NPM serves its admin interface over **unencrypted HTTP on container port 81**.
Two ways to keep that safe in production:

1. **Bind it to a trusted interface only.** In the compose file, publish the
   admin port on loopback (and reach it via an SSH tunnel or a VPN):
   ```yaml
   - "127.0.0.1:${PORT_ADMIN:-8080}:81"
   ```
2. **Proxy the UI through NPM itself** — create a proxy host (e.g.
   `npm.example.com`) forwarding to `127.0.0.1:81` with a Let's Encrypt
   certificate and an access list. Then you can stop publishing 8080 entirely.

This follows least-privilege: the management plane is never exposed in clear text
on a public interface.

## Internal ports are fixed

The container always listens on `80`, `443` and `81`. The `PORT_*` variables
change only the **host** side of each mapping (`PORT_ADMIN:81`, etc.). Keeping the
container ports fixed is what lets the bundled healthcheck and the generated
nginx configs stay consistent. To run the admin UI on a different external port:

```env
PORT_ADMIN=9000      # http://<host>:9000 -> container :81
```

## <a id="stream-ports"></a>Stream ports (TCP/UDP forwarding)

NPM can forward raw **TCP/UDP** streams (UI: **Hosts → Streams**) — e.g. FTP,
SMTP, game servers, DNS. nginx serving the stream is ready, but Docker still has
to publish the host port. Add each stream port to the compose file's `ports:`
list:

```yaml
ports:
  - "${PORT_HTTP:-80}:80"
  - "${PORT_HTTPS:-443}:443"
  - "${PORT_HTTPS:-443}:443/udp"
  - "${PORT_ADMIN:-8080}:81"
  # Stream examples — must match the Incoming Port set in the UI:
  - "21:21"        # FTP            (TCP)
  - "25:25"        # SMTP           (TCP)
  - "53:53/udp"    # DNS            (UDP)
```

A stream port published here but not configured in the UI does nothing; a stream
configured in the UI but not published here is unreachable from outside. They
must match.

## Custom nginx configuration

NPM supports drop-in nginx snippets under `/data/nginx/custom/` (in the
`npm-data` volume) without rebuilding the image — e.g. `http_top.conf`,
`server_proxy.conf`, `stream.conf`. The edition's HTTP/3 wiring does **not** use
these hooks (it patches the listen template directly), so they remain entirely
free for your own customisations. See the upstream
[advanced configuration](https://nginxproxymanager.com/advanced-config/) docs.
