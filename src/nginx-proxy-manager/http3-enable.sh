#!/usr/bin/env bash
# =============================================================================
# BAUER GROUP NGINX Proxy Manager - HTTP/3 (QUIC) activation
# =============================================================================
# The upstream nginx (OpenResty) already ships with --with-http_v3_module and
# OpenSSL 3.5, so QUIC capability is compiled in — it just isn't wired into the
# config. This script wires it in, deterministically, on every boot, BEFORE
# s6/NPM regenerate the nginx configs.
#
# It touches exactly two files, both baked into the image (not the data volume):
#
#   1. /etc/nginx/conf.d/default.conf   (NPM's static "First 443 Host")
#      -> owns the `reuseport` QUIC socket EXACTLY ONCE. nginx requires the
#         reuseport flag on a given address:port to appear in a single server
#         block; every real proxy host then attaches with a plain `quic` listener.
#
#   2. /app/templates/_listen.conf      (the per-host listen template)
#      -> adds `listen 443 quic; http3 on;` to every TLS-enabled proxy host plus
#         an Alt-Svc advertisement. We use `more_set_headers` (headers-more, which
#         is statically compiled in) instead of `add_header`, because nginx drops
#         inherited `add_header` directives in any location that sets its own
#         (e.g. HSTS) — `more_set_headers` survives that and reliably advertises H3.
#
# IPv6 is intentionally NOT special-cased for default.conf: NPM's own
# prepare/50-ipv6.sh comments/uncomments every `listen [::]` line (ours included)
# based on DISABLE_IPV6. For the template we reuse NPM's existing `{% if ipv6 %}`.
#
# The script works against pristine `.orig` snapshots taken at build time, so it
# is fully idempotent and reversible: enable = restore + inject, disable = restore.
# =============================================================================
set -euo pipefail

LISTEN_TPL="/app/templates/_listen.conf"
DEFAULT_CONF="/etc/nginx/conf.d/default.conf"

# is_true "yes|true|1|on" -> 0 (true), else 1 (false)
is_true() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1 | true | yes | on | enable | enabled) return 0 ;;
    *) return 1 ;;
  esac
}

restore_pristine() {
  [ -f "${DEFAULT_CONF}.orig" ] && cp -f "${DEFAULT_CONF}.orig" "$DEFAULT_CONF"
  [ -f "${LISTEN_TPL}.orig" ] && cp -f "${LISTEN_TPL}.orig" "$LISTEN_TPL"
}

inject_default_conf() {
  # Add the single reuseport-owning QUIC listener to the default 443 server.
  # NPM's 50-ipv6.sh will comment the [::] line later if DISABLE_IPV6 is set.
  awk '
    { print }
    /listen \[::\]:443 ssl;/ && !injected {
      print "\tlisten 443 quic reuseport;       # BG-HTTP3"
      print "\tlisten [::]:443 quic reuseport;  # BG-HTTP3"
      injected = 1
    }
  ' "$DEFAULT_CONF" > "${DEFAULT_CONF}.tmp" && mv "${DEFAULT_CONF}.tmp" "$DEFAULT_CONF"
}

inject_listen_template() {
  # Add per-host QUIC listeners, http3 and the Alt-Svc advertisement inside the
  # existing `{% if certificate %}` block (right after `listen 443 ssl;`).
  awk '
    { print }
    /^  listen 443 ssl;/ && !injected {
      print "  listen 443 quic;                 # BG-HTTP3"
      print "{% if ipv6 -%}"
      print "  listen [::]:443 quic;            # BG-HTTP3"
      print "{% endif %}"
      print "  http3 on;                        # BG-HTTP3"
      print "  more_set_headers \"Alt-Svc: h3=\\\":443\\\"; ma=86400\";  # BG-HTTP3"
      injected = 1
    }
  ' "$LISTEN_TPL" > "${LISTEN_TPL}.tmp" && mv "${LISTEN_TPL}.tmp" "$LISTEN_TPL"
}

main() {
  # Always start from the pristine, image-baked files.
  restore_pristine

  if is_true "${NPM_HTTP3_ENABLE:-true}"; then
    [ -f "$DEFAULT_CONF" ] && inject_default_conf
    [ -f "$LISTEN_TPL" ] && inject_listen_template
    echo "[http3] HTTP/3 (QUIC) enabled — reuseport socket + per-host quic listeners + Alt-Svc"
  else
    echo "[http3] HTTP/3 (QUIC) disabled — serving HTTP/1.1 + HTTP/2 only"
  fi
}

main "$@"
