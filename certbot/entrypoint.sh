#!/bin/sh
set -eu

WEBROOT=/var/www/certbot

le_domain_from_nginx_conf() {
    conf="${1:-/etc/nginx/nginx.conf}"
    [ -f "$conf" ] || return 0
    grep -E '^[[:space:]]*ssl_certificate[[:space:]]+/etc/letsencrypt/live/[^[:space:]/]+/fullchain\.pem' "$conf" 2>/dev/null |
        head -1 |
        sed -n 's|.*\/etc/letsencrypt/live/\([^/]*\)/fullchain.pem.*|\1|p'
}

resolve_domain() {
    NGINX_DOMAIN=$(le_domain_from_nginx_conf /etc/nginx/nginx.conf)
    if [ -n "${CERTBOT_DOMAIN:-}" ]; then
        DOMAIN="${CERTBOT_DOMAIN}"
    else
        DOMAIN="${NGINX_DOMAIN}"
    fi
    if [ -z "$DOMAIN" ]; then
        echo "Could not determine hostname for certificates: set CERTBOT_DOMAIN in .env or add ssl_certificate .../etc/letsencrypt/live/<name>/fullchain.pem in nginx.conf." >&2
        exit 1
    fi
    if [ -n "${CERTBOT_DOMAIN:-}" ] && [ -n "${NGINX_DOMAIN}" ] && [ "${CERTBOT_DOMAIN}" != "${NGINX_DOMAIN}" ]; then
        echo "CERTBOT_DOMAIN (${CERTBOT_DOMAIN}) does not match ssl_certificate path in nginx.conf (${NGINX_DOMAIN}). Fix one of them so they match." >&2
        exit 1
    fi
}

# One-shot: mkdir -p live/<domain>/ and self-signed PEMs so nginx can start before real issuance.
bootstrap_self_signed_if_needed() {
    LIVE="/etc/letsencrypt/live/${DOMAIN}"
    echo "certbot bootstrap: ensuring placeholder TLS files under ${LIVE}"
    mkdir -p "${LIVE}"
    if [ ! -f "${LIVE}/fullchain.pem" ] || [ ! -f "${LIVE}/privkey.pem" ]; then
        openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
            -subj "/CN=${DOMAIN}" \
            -keyout "${LIVE}/privkey.pem" \
            -out "${LIVE}/fullchain.pem"
    fi
}

if [ "${1:-}" = "bootstrap" ]; then
    resolve_domain
    bootstrap_self_signed_if_needed
    exit 0
fi

resolve_domain

# Stored in renewal config; use a fixed path (certbot image has no curl).
DEPLOY_HOOK="python3 /usr/local/bin/reload-via-docker-socket.py || true"

# Do not use urllib on GET / — nginx redirects HTTP to HTTPS and urllib follows, then fails on the self-signed cert.
echo "Waiting for nginx to listen on TCP port 80..."
i=0
while [ "${i}" -lt 90 ]; do
    if python3 -c "import socket; s=socket.create_connection(('nginx', 80), timeout=5); s.close()" >/dev/null 2>&1; then
        break
    fi
    i=$((i + 1))
    sleep 2
done
if [ "${i}" -ge 90 ]; then
    echo "nginx did not become reachable in time." >&2
    exit 1
fi

if certbot certificates 2>/dev/null | grep -Fq "Certificate Name: ${DOMAIN}"; then
    echo "Certbot already manages a certificate for ${DOMAIN}."
else
    echo "Requesting Let's Encrypt certificate for ${DOMAIN} (webroot)..."
    if [ -n "${CERTBOT_EMAIL:-}" ]; then
        certbot certonly \
            --webroot -w "${WEBROOT}" \
            -d "${DOMAIN}" \
            --email "${CERTBOT_EMAIL}" \
            --agree-tos \
            --non-interactive \
            --no-eff-email \
            --deploy-hook "${DEPLOY_HOOK}"
    else
        echo "CERTBOT_EMAIL is empty; registering ACME account without an email (--register-unsafely-without-email)."
        certbot certonly \
            --webroot -w "${WEBROOT}" \
            -d "${DOMAIN}" \
            --register-unsafely-without-email \
            --agree-tos \
            --non-interactive \
            --deploy-hook "${DEPLOY_HOOK}"
    fi
fi

trap exit TERM
echo "Running periodic certbot renew (every 12h)..."
while true; do
    # deploy-hook from the initial certonly is stored in the renewal config.
    certbot renew --non-interactive
    sleep 12h &
    wait "${!}"
done
