#!/bin/bash
set -e

# XMPP Home Server - Entrypoint Script
# Handles auto-configuration on container startup

echo "=========================================="
echo "  XMPP Home Server - Starting..."
echo "=========================================="

# ---------- Environment Variables ----------

export DOMAIN="${DOMAIN:-home.local}"
export ADMIN_JID="${ADMIN_JID:-}"
export ENABLE_MDNS="${ENABLE_MDNS:-true}"
export USE_LETSENCRYPT="${USE_LETSENCRYPT:-false}"
export LETSENCRYPT_PATH="${LETSENCRYPT_PATH:-/etc/letsencrypt/live/${DOMAIN}}"
export FILE_SHARE_MAX_SIZE="${FILE_SHARE_MAX_SIZE:-10485760}"
export FILE_SHARE_DAILY_QUOTA="${FILE_SHARE_DAILY_QUOTA:-104857600}"
export MUC_DOMAIN="${MUC_DOMAIN:-rooms.${DOMAIN}}"

# HTTP/HTTPS for file upload (default: HTTP for home networks, HTTPS for internet)
export HTTP_UPLOAD_SECURE="${HTTP_UPLOAD_SECURE:-false}"

# Set HTTP URLs based on secure mode
if [ "${HTTP_UPLOAD_SECURE}" = "true" ]; then
    export HTTP_EXTERNAL_URL="https://${DOMAIN}:5281/"
    export HTTP_UPLOAD_PORT="5281"
else
    export HTTP_EXTERNAL_URL="http://${DOMAIN}:5280/"
    export HTTP_UPLOAD_PORT="5280"
fi

echo "[CONFIG] Domain: ${DOMAIN}"
echo "[CONFIG] Admin JID: ${ADMIN_JID:-none}"
echo "[CONFIG] mDNS enabled: ${ENABLE_MDNS}"
echo "[CONFIG] Let's Encrypt: ${USE_LETSENCRYPT}"
echo "[CONFIG] HTTP Upload Secure: ${HTTP_UPLOAD_SECURE}"
echo "[CONFIG] File upload URL: ${HTTP_EXTERNAL_URL}"
echo "[CONFIG] Max file size: ${FILE_SHARE_MAX_SIZE} bytes"

# ---------- Directory Setup ----------

echo "[SETUP] Ensuring directories exist..."
mkdir -p /data/certs /data/prosody /data/uploads /var/run/prosody /var/run/dbus

# Set ownership only on subdirectories (not /data itself, as users.txt may be mounted read-only)
chown -R prosody:prosody /data/certs /data/prosody /data/uploads /var/run/prosody

# ---------- Certificate Handling ----------

CERT_DIR="/data/certs"
CERT_FILE="${CERT_DIR}/${DOMAIN}.crt"
KEY_FILE="${CERT_DIR}/${DOMAIN}.key"

if [ "${USE_LETSENCRYPT}" = "true" ]; then
    echo "[CERTS] Using Let's Encrypt certificates..."

    if [ -f "${LETSENCRYPT_PATH}/fullchain.pem" ] && [ -f "${LETSENCRYPT_PATH}/privkey.pem" ]; then
        echo "[CERTS] Linking Let's Encrypt certificates..."
        ln -sf "${LETSENCRYPT_PATH}/fullchain.pem" "${CERT_FILE}"
        ln -sf "${LETSENCRYPT_PATH}/privkey.pem" "${KEY_FILE}"
        echo "[CERTS] Let's Encrypt certificates linked successfully"
    else
        echo "[ERROR] Let's Encrypt certificates not found at ${LETSENCRYPT_PATH}"
        echo "[ERROR] Please ensure certificates exist or set USE_LETSENCRYPT=false"
        exit 1
    fi
elif [ ! -f "${CERT_FILE}" ] || [ ! -f "${KEY_FILE}" ]; then
    echo "[CERTS] Generating self-signed certificates for ${DOMAIN}..."

    openssl req -new -x509 -days 3650 -nodes \
        -out "${CERT_FILE}" \
        -keyout "${KEY_FILE}" \
        -subj "/CN=${DOMAIN}/O=XMPP Home Server" \
        -addext "subjectAltName=DNS:${DOMAIN},DNS:rooms.${DOMAIN},DNS:*.${DOMAIN}" \
        2>/dev/null

    chmod 640 "${KEY_FILE}"
    chown prosody:prosody "${CERT_FILE}" "${KEY_FILE}"

    echo "[CERTS] Self-signed certificates generated (valid for 10 years)"
else
    echo "[CERTS] Using existing certificates"
fi

# ---------- Generate Prosody Configuration ----------

echo "[CONFIG] Generating Prosody configuration..."

# Use envsubst to replace environment variables in template
envsubst '${DOMAIN} ${ADMIN_JID} ${FILE_SHARE_MAX_SIZE} ${FILE_SHARE_DAILY_QUOTA} ${HTTP_EXTERNAL_URL}' \
    < /etc/prosody/prosody.cfg.lua.template \
    > /etc/prosody/prosody.cfg.lua

chown prosody:prosody /etc/prosody/prosody.cfg.lua
echo "[CONFIG] Prosody configuration generated"

# ---------- User Creation ----------

USERS_FILE="/data/users.txt"

if [ -f "${USERS_FILE}" ]; then
    echo "[USERS] Processing users from ${USERS_FILE}..."

    while IFS=: read -r username password || [ -n "$username" ]; do
        # Skip empty lines and comments
        [[ -z "$username" || "$username" =~ ^[[:space:]]*# ]] && continue

        # Trim whitespace
        username=$(echo "$username" | tr -d '[:space:]')
        password=$(echo "$password" | tr -d '[:space:]')

        if [ -n "$username" ] && [ -n "$password" ]; then
            # Check if user already exists
            if prosodyctl mod_listusers 2>/dev/null | grep -q "^${username}@${DOMAIN}$"; then
                echo "[USERS] User ${username}@${DOMAIN} already exists, skipping"
            else
                echo "[USERS] Creating user: ${username}@${DOMAIN}"
                prosodyctl register "${username}" "${DOMAIN}" "${password}" 2>/dev/null || true
            fi
        fi
    done < "${USERS_FILE}"

    echo "[USERS] User processing complete"
else
    echo "[USERS] No users.txt found at ${USERS_FILE}"
    echo "[USERS] Copy users.txt.example to data/users.txt and restart"
fi

# ---------- Shared Roster Groups ----------

GROUPS_FILE="/data/prosody/groups.txt"

if [ -f "${USERS_FILE}" ]; then
    echo "[GROUPS] Generating shared roster group..."

    # Create groups file header
    echo "[Family]" > "${GROUPS_FILE}"

    # Add all users to the Family group
    while IFS=: read -r username password || [ -n "$username" ]; do
        # Skip empty lines and comments
        [[ -z "$username" || "$username" =~ ^[[:space:]]*# ]] && continue

        # Trim whitespace
        username=$(echo "$username" | tr -d '[:space:]')

        if [ -n "$username" ]; then
            # Capitalize first letter for display name (portable for Alpine/BusyBox)
            first_char=$(echo "$username" | cut -c1 | tr '[:lower:]' '[:upper:]')
            rest_chars=$(echo "$username" | cut -c2-)
            display_name="${first_char}${rest_chars}"
            echo "${username}@${DOMAIN}=${display_name}" >> "${GROUPS_FILE}"
        fi
    done < "${USERS_FILE}"

    chown prosody:prosody "${GROUPS_FILE}"
    echo "[GROUPS] All users added to 'Family' group (auto-contacts enabled)"
else
    # Create empty groups file if no users
    echo "[Family]" > "${GROUPS_FILE}"
    chown prosody:prosody "${GROUPS_FILE}"
fi

# ---------- Default MUC Room Creation ----------

echo "[MUC] Default 'Family' room will be created on first join"
# Note: Prosody creates persistent rooms when first joined with the right config
# The room family@rooms.${DOMAIN} will be auto-created as persistent

# ---------- mDNS Setup (Avahi) ----------

if [ "${ENABLE_MDNS}" = "true" ]; then
    echo "[MDNS] Starting mDNS advertisement..."

    # Update Avahi service file with correct domain
    cat > /etc/avahi/services/xmpp.service << EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>XMPP Home Server (${DOMAIN})</name>
  <service>
    <type>_xmpp-client._tcp</type>
    <port>5222</port>
    <txt-record>txtvers=1</txt-record>
    <txt-record>domain=${DOMAIN}</txt-record>
  </service>
</service-group>
EOF

    # Start D-Bus (required for Avahi)
    if [ ! -f /var/run/dbus/pid ]; then
        dbus-daemon --system --fork 2>/dev/null || true
    fi

    # Start Avahi daemon
    avahi-daemon --daemonize --no-chroot 2>/dev/null || echo "[MDNS] Avahi start failed (may need --network=host)"

    echo "[MDNS] mDNS advertisement started"
else
    echo "[MDNS] mDNS disabled"
fi

# ---------- Start Prosody ----------

echo "=========================================="
echo "  XMPP Home Server Ready!"
echo "=========================================="
echo ""
echo "  Domain: ${DOMAIN}"
echo "  Client port: 5222"
echo "  File upload: ${HTTP_UPLOAD_PORT} (${HTTP_UPLOAD_SECURE:+HTTPS}${HTTP_UPLOAD_SECURE:-HTTP})"
echo ""
echo "  Connect with Pidgin/Gajim/Conversations"
echo "  JID format: username@${DOMAIN}"
echo ""
echo "=========================================="

# Run Prosody as prosody user (not root)
exec su-exec prosody prosody
