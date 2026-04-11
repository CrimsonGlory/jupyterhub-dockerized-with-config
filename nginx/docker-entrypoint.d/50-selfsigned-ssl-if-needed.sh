#!/bin/sh
set -eu

# Temporary self-signed cert so nginx can start before Let's Encrypt issues a real one.
# Paths must match ssl_certificate / ssl_certificate_key in nginx.conf (live/<domain>/).

DOMAIN="${CERTBOT_DOMAIN:-course.example.com}"
LIVE="/etc/letsencrypt/live/${DOMAIN}"

if [ ! -f "${LIVE}/fullchain.pem" ] || [ ! -f "${LIVE}/privkey.pem" ]; then
    mkdir -p "${LIVE}"
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
        -subj "/CN=${DOMAIN}" \
        -keyout "${LIVE}/privkey.pem" \
        -out "${LIVE}/fullchain.pem" \
        >/dev/null 2>&1
fi
