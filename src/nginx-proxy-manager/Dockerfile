# ===============================================================================
# BAUER GROUP NGINX Proxy Manager - Container Image
# ===============================================================================
# Thin, professional wrapper around the official jc21/nginx-proxy-manager image.
#
# Adds:
#   - OCI image labels + BAUER GROUP supply chain (own GHCR image, SBOM, scans)
#   - Turnkey HTTP/3 (QUIC): activates the QUIC support that is ALREADY compiled
#     into the upstream nginx (OpenResty + OpenSSL 3.5) — no nginx rebuild
#   - A branded boot banner that echoes the effective runtime configuration
#
# It deliberately keeps the upstream runtime contract intact: same data dir
# (/data), same ports (80/443/81), same healthcheck (/usr/bin/check-health), and
# s6-overlay (`/init`) stays PID 1 for correct signal handling.
#
# Documentation: https://github.com/bauer-group/CS-NGINXProxy
# ===============================================================================

# ---------------------------------------------------------------------------
# Build Arguments
# ---------------------------------------------------------------------------
# Floating tag: tracks the latest NPM 2.x (major pinned to avoid a breaking jump
# to 3.x). The base-image monitor rebuilds when the digest moves.
ARG NPM_REPOSITORY=jc21/nginx-proxy-manager
ARG NPM_VERSION=2

# ---------------------------------------------------------------------------
# Base Image
# ---------------------------------------------------------------------------
FROM ${NPM_REPOSITORY}:${NPM_VERSION}

# ---------------------------------------------------------------------------
# Metadata Labels (Legacy)
# ---------------------------------------------------------------------------
LABEL vendor="BAUER GROUP"
LABEL maintainer="Karl Bauer <karl.bauer@bauer-group.com>"

# ---------------------------------------------------------------------------
# OCI Image Spec Labels
# https://github.com/opencontainers/image-spec/blob/main/annotations.md
# ---------------------------------------------------------------------------
LABEL org.opencontainers.image.title="NGINX Proxy Manager"
LABEL org.opencontainers.image.description="Nginx Proxy Manager reverse proxy - BAUER GROUP Edition (turnkey HTTP/3 QUIC, branded boot, CI/CD supply chain)"
LABEL org.opencontainers.image.vendor="BAUER GROUP"
LABEL org.opencontainers.image.authors="Karl Bauer <karl.bauer@bauer-group.com>"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.source="https://github.com/bauer-group/CS-NGINXProxy"
LABEL org.opencontainers.image.url="https://github.com/bauer-group/CS-NGINXProxy"
LABEL org.opencontainers.image.documentation="https://github.com/bauer-group/CS-NGINXProxy#readme"
LABEL org.opencontainers.image.version="0.1.0"

# ---------------------------------------------------------------------------
# Edition defaults (overridable via compose .env)
# ---------------------------------------------------------------------------
ENV NPM_HTTP3_ENABLE=true

# ---------------------------------------------------------------------------
# Pristine snapshots for reversible HTTP/3 wiring
# ---------------------------------------------------------------------------
# http3-enable.sh restores these on every boot before (re)injecting, so the
# activation is deterministic and a simple env toggle fully reverts it.
RUN cp -f /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.orig \
 && cp -f /app/templates/_listen.conf    /app/templates/_listen.conf.orig

# ---------------------------------------------------------------------------
# Custom scripts (banner + HTTP/3 activation; s6 `/init` stays PID 1)
# ---------------------------------------------------------------------------
COPY docker-entrypoint-custom.sh /usr/local/bin/docker-entrypoint-custom.sh
COPY http3-enable.sh             /usr/local/bin/http3-enable.sh
RUN chmod a+rx /usr/local/bin/docker-entrypoint-custom.sh /usr/local/bin/http3-enable.sh

# ---------------------------------------------------------------------------
# Ports
# ---------------------------------------------------------------------------
# 80      Public HTTP
# 443/tcp Public HTTPS (HTTP/1.1 + HTTP/2)
# 443/udp Public HTTPS (HTTP/3 / QUIC)
# 81      Admin web UI (plain HTTP)
EXPOSE 80 443 443/udp 81

# ---------------------------------------------------------------------------
# Health Check (mirrors upstream — bundled checker hits the local admin API)
# ---------------------------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
    CMD /usr/bin/check-health

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
# Our shim runs first (banner + HTTP/3 wiring), then exec's the upstream s6 init
# which becomes PID 1.
ENTRYPOINT ["/usr/local/bin/docker-entrypoint-custom.sh"]
CMD ["/init"]
