# HTTP/3 & QUIC

This edition serves **HTTP/3** (QUIC over UDP/443) in addition to HTTP/1.1 and
HTTP/2, with no nginx recompile and no fork of Nginx Proxy Manager.

## Why it works without rebuilding nginx

The upstream `jc21/nginx-proxy-manager` image already ships an OpenResty build
with QUIC support compiled in. Straight from the image (`nginx -V`):

```text
nginx version: openresty/1.29.2.5
built with OpenSSL 3.5.x
configure arguments: ... --with-http_v2_module --with-http_v3_module --with-stream ...
```

`--with-http_v3_module` + OpenSSL 3.5 (which carries the QUIC implementation)
means HTTP/3 is a **configuration** concern, not a build concern. Stock NPM
simply never writes the `quic` listeners into its generated configs. This edition
does.

## What the edition changes

On every boot, **before** s6/NPM regenerate the nginx configs,
`http3-enable.sh` wires QUIC into exactly two files (both baked into the image,
restored from pristine `.orig` snapshots each time so the change is idempotent
and reversible):

### 1. The reuseport socket owner — `/etc/nginx/conf.d/default.conf`

nginx requires the `reuseport` flag on a given `address:port` to appear in
**exactly one** server block. NPM's static "First 443 Host" default server is the
perfect single owner:

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    listen 443 quic reuseport;       # BG-HTTP3  <- owns the QUIC socket, once
    listen [::]:443 quic reuseport;  # BG-HTTP3
    server_name localhost;
    ssl_reject_handshake on;
    return 444;
}
```

### 2. The per-host listeners — `/app/templates/_listen.conf`

Every TLS-enabled proxy host then **attaches** to that socket with a plain `quic`
listener (no `reuseport`), turns on HTTP/3, and advertises it:

```nginx
listen 443 ssl;
listen 443 quic;                 # BG-HTTP3  <- attaches, no reuseport
listen [::]:443 quic;            # BG-HTTP3  (only when IPv6 is enabled)
http3 on;                        # BG-HTTP3
more_set_headers "Alt-Svc: h3=\":443\"; ma=86400";  # BG-HTTP3
```

### Why `more_set_headers` and not `add_header`

Browsers only switch to HTTP/3 after they see an `Alt-Svc` header over HTTP/2.
nginx **drops inherited `add_header` directives** in any `location` that sets its
own (NPM's `location /` sets HSTS), which would silently swallow an `add_header
Alt-Svc` placed at server level. `more_set_headers` (from the `headers-more`
module, statically compiled into the image) is immune to that reset and applies
to every response — so HTTP/3 is reliably advertised even with HSTS on.

### IPv6 is handled by NPM, not by us

We do not special-case IPv6 for `default.conf`: NPM's own `prepare/50-ipv6.sh`
comments/uncomments every `listen [::]` line — ours included — based on
`DISABLE_IPV6`. For the per-host template we reuse NPM's existing `{% if ipv6 %}`
guard. Set `DISABLE_IPV6=true` on IPv6-less hosts and the QUIC IPv6 listeners
disappear cleanly alongside the rest.

## Enabling / disabling

HTTP/3 is **on by default** (`NPM_HTTP3_ENABLE=true`). To turn it off and serve
HTTP/1.1 + HTTP/2 only:

```env
NPM_HTTP3_ENABLE=false
```

Then `docker compose ... up -d` to recreate the container. Because the script
always starts from the pristine `.orig` files, disabling fully reverts the config
to stock NPM.

## Firewall — the one thing you must not forget

QUIC is UDP. The compose files publish `443/udp`, but your host/network firewall
must also allow **inbound UDP/443**:

```bash
# ufw
sudo ufw allow 443/udp

# firewalld
sudo firewall-cmd --permanent --add-port=443/udp && sudo firewall-cmd --reload
```

Without it, browsers never complete the QUIC handshake and silently fall back to
HTTP/2 — everything still works, just without HTTP/3.

## Verifying

```bash
# 1. nginx accepts the QUIC config
docker compose -f docker-compose.production.yml exec nginx-proxy-manager nginx -t

# 2. Alt-Svc is advertised (after you create a TLS proxy host)
curl -sI https://your.domain | grep -i alt-svc
# -> alt-svc: h3=":443"; ma=86400

# 3. A real HTTP/3 request (curl built with HTTP/3, or use the browser devtools
#    Network tab -> Protocol column -> "h3")
curl --http3 -sI https://your.domain | head -n1
```

In Chrome/Firefox devtools, the **Protocol** column shows `h3` once the browser
has upgraded (it uses H2 for the first request, then H3 after seeing `Alt-Svc`).

## Caveat: existing hosts on a migrated data volume

NPM does **not** regenerate existing proxy-host configs on boot. So:

- **Fresh deployments / new hosts** — get HTTP/3 automatically: the listen
  template is patched before any host is created.
- **A pre-existing `npm-data` volume** — hosts created by stock NPM keep their
  old generated config (no `quic` listeners) until they are regenerated. Trigger
  it once by editing & saving each proxy host in the UI (any trivial change), or
  by toggling a global setting that forces a rewrite. New and re-saved hosts pick
  up HTTP/3 from then on.

## Scope & limitations

- HTTP/3 applies to **TLS-enabled proxy hosts** (QUIC requires TLS). Plain-HTTP
  hosts and the `:80` listeners are unaffected.
- It is **global** for all TLS hosts, not a per-host UI toggle — adding a per-host
  switch would require backend changes to NPM, which this thin wrapper avoids by
  design.
- The `:81` admin UI is HTTP/1.1 only (it is not meant to be public; see
  [configuration.md](configuration.md#the-admin-ui-is-plain-http)).
