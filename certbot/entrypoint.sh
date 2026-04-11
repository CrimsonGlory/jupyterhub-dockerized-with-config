#!/bin/sh
set -eu

DOMAIN="${CERTBOT_DOMAIN:?CERTBOT_DOMAIN is required}"
WEBROOT=/var/www/certbot
NGINX_CONTAINER=nginx
DOCKER_API_VERSION=v1.41

# Stored in renewal config; keep literal paths (no env vars) for reliability after renew.
DEPLOY_HOOK="sh -c 'curl -fsS --unix-socket /var/run/docker.sock -X POST http://localhost/${DOCKER_API_VERSION}/containers/${NGINX_CONTAINER}/kill?signal=HUP >/dev/null 2>&1 || true'"

echo "Waiting for nginx to accept HTTP on port 80..."
i=0
while [ "${i}" -lt 90 ]; do
    if curl -sS -o /dev/null "http://nginx:80/" 2>/dev/null; then
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
