# XMPP Home Server - Prosody in Docker
# Offline-first XMPP server for families
# Multi-arch: ARM64 (Pi4) and x86_64

FROM alpine:3.21

LABEL maintainer="XMPP Home Server"
LABEL description="Offline-first XMPP server for families"
LABEL version="1.0"

# Install Prosody and dependencies
RUN apk add --no-cache \
    prosody \
    lua5.4-sec \
    lua5.4-expat \
    lua5.4-socket \
    lua5.4-filesystem \
    avahi \
    avahi-tools \
    dbus \
    openssl \
    ca-certificates \
    bash \
    gettext \
    su-exec \
    && rm -rf /var/cache/apk/*

# Create necessary directories
RUN mkdir -p \
    /data/certs \
    /data/prosody \
    /data/uploads \
    /var/run/prosody \
    /var/run/dbus \
    /etc/avahi/services \
    && chown -R prosody:prosody /data /var/run/prosody

# Copy configuration files
COPY prosody.cfg.lua.template /etc/prosody/prosody.cfg.lua.template
COPY entrypoint.sh /entrypoint.sh
COPY avahi-xmpp.service /etc/avahi/services/xmpp.service

# Make entrypoint executable
RUN chmod +x /entrypoint.sh

# Expose XMPP ports
# 5222: Client-to-server (c2s)
# 5269: Server-to-server (s2s)
# 5280: HTTP (BOSH, WebSocket)
# 5281: HTTPS (file upload)
# 5000: Proxy65 file transfer
EXPOSE 5222 5269 5280 5281 5000

# Persistent data volume
VOLUME ["/data"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD prosodyctl status || exit 1

# Entrypoint
ENTRYPOINT ["/entrypoint.sh"]
