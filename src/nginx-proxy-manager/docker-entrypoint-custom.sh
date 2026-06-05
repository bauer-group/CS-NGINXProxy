#!/usr/bin/env bash
# =============================================================================
# BAUER GROUP NGINX Proxy Manager - Custom Entrypoint
# =============================================================================
# A thin shim in front of the upstream s6-overlay init (`/init`). It:
#   1. prints a branded banner echoing the effective runtime configuration
#   2. activates / deactivates HTTP/3 (QUIC) via http3-enable.sh — this MUST run
#      before `/init`, so that when NPM's s6 services regenerate the nginx
#      configs they pick up the patched listen template
#   3. exec's `/init`, which then becomes PID 1 (s6 signal handling unchanged)
#
# No secrets, no TLS handling of our own (NPM/certbot own that), no DB logic.
# =============================================================================
set -euo pipefail

# --- Defaults (mirrored in the Dockerfile / .env.example) --------------------
: "${NPM_HTTP3_ENABLE:=true}"
: "${DISABLE_IPV6:=false}"
: "${DB_SQLITE_FILE:=/data/database.sqlite}"

log() { printf '%s\n' "$*"; }

banner() {
  log "==================================================="
  log " BAUER GROUP NGINX Proxy Manager"
  log "==================================================="
  log "Hostname            : ${HOSTNAME:-unknown}"
  log "Timezone            : ${TZ:-Etc/UTC}"
  log "Database (SQLite)    : ${DB_SQLITE_FILE}"
  log "HTTP/3 (QUIC/UDP)    : ${NPM_HTTP3_ENABLE}"
  log "IPv6 disabled        : ${DISABLE_IPV6}"
  log "Container ports      : 80 (HTTP) / 443 (HTTPS+QUIC) / 81 (Admin UI)"
  log "Data directory      : /data"
  log "Certificates        : /etc/letsencrypt"
  log "==================================================="
  if [ -n "${INITIAL_ADMIN_EMAIL:-}" ] && [ -n "${INITIAL_ADMIN_PASSWORD:-}" ]; then
    log "Admin account       : provisioned from INITIAL_ADMIN_EMAIL"
    log "  (${INITIAL_ADMIN_EMAIL}) on first start only"
  else
    log "First run? Open the admin UI and complete the"
    log "setup wizard to create your administrator account."
    log "(Or set INITIAL_ADMIN_EMAIL + INITIAL_ADMIN_PASSWORD"
    log " to provision it automatically.)"
  fi
  log "==================================================="
}

banner

# Wire up (or tear down) HTTP/3 before s6/NPM regenerate the nginx configs.
if [ -x /usr/local/bin/http3-enable.sh ]; then
  /usr/local/bin/http3-enable.sh || log "[http3] WARNING: activation script failed, continuing with stock config"
fi

log "Starting NGINX Proxy Manager via s6-overlay: $*"
exec "$@"
