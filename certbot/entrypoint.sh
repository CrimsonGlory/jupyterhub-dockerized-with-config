#!/bin/sh
set -eu

WEBROOT=/var/www/certbot
RELOAD_HOOK="/usr/local/bin/reload-via-docker-socket.py"

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

# True iff certbot lists this exact lineage name (not e.g. example.com when only example.com-0001 exists).
has_lineage_name() {
    name="$1"
    certbot certificates 2>/dev/null | sed -n 's/^  Certificate Name: //p' | grep -Fxq "$name"
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

# Remove openssl bootstrap dirs so certonly can use .../live/<domain>/ (avoids -0001 and "live directory exists").
clear_unmanaged_live_for_domain() {
    LIVE="/etc/letsencrypt/live/${DOMAIN}"
    if has_lineage_name "${DOMAIN}"; then
        return 0
    fi
    if [ -d "${LIVE}" ] || [ -d "/etc/letsencrypt/archive/${DOMAIN}" ] || [ -f "/etc/letsencrypt/renewal/${DOMAIN}.conf" ]; then
        echo "Removing unmanaged paths for ${DOMAIN} so certbot can claim the standard lineage (archive/live/renewal)."
        rm -rf "/etc/letsencrypt/archive/${DOMAIN}" "/etc/letsencrypt/live/${DOMAIN}"
        rm -f "/etc/letsencrypt/renewal/${DOMAIN}.conf"
    fi
}

# Renewal configs with no matching lineage, or a corrupt renewal INI, make `certbot renew` exit non-zero.
# A lineage can still appear in `certbot certificates` while its renewal file is broken (e.g. bad deploy_hook).
prune_bad_renewal_configs() {
    for cfg in /etc/letsencrypt/renewal/*.conf; do
        [ -f "$cfg" ] || continue
        base=$(basename "$cfg" .conf)
        remove=""
        if ! has_lineage_name "${base}"; then
            remove=1
        else
            log=$(mktemp)
            if ! certbot renew --cert-name "${base}" --dry-run >"${log}" 2>&1; then
                if grep -qiE 'parsefail|Renewal configuration file .* is broken|missing a required file reference' "${log}"; then
                    remove=1
                fi
            fi
            rm -f "${log}"
        fi
        if [ -n "$remove" ]; then
            echo "Removing renewal file ${cfg} (no matching lineage name, or renewal config broken / unparseable)."
            rm -f "${cfg}"
        fi
    done
}

if [ "${1:-}" = "bootstrap" ]; then
    resolve_domain
    bootstrap_self_signed_if_needed
    exit 0
fi

resolve_domain

chmod +x "${RELOAD_HOOK}" 2>/dev/null || true

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

if has_lineage_name "${DOMAIN}"; then
    echo "Certbot already manages a certificate named ${DOMAIN}."
else
    clear_unmanaged_live_for_domain
    echo "Requesting Let's Encrypt certificate for ${DOMAIN} (webroot)..."
    if [ -n "${CERTBOT_EMAIL:-}" ]; then
        certbot certonly \
            --webroot -w "${WEBROOT}" \
            -d "${DOMAIN}" \
            --email "${CERTBOT_EMAIL}" \
            --agree-tos \
            --non-interactive \
            --no-eff-email \
            --deploy-hook "${RELOAD_HOOK}"
    else
        echo "CERTBOT_EMAIL is empty; registering ACME account without an email (--register-unsafely-without-email)."
        certbot certonly \
            --webroot -w "${WEBROOT}" \
            -d "${DOMAIN}" \
            --register-unsafely-without-email \
            --agree-tos \
            --non-interactive \
            --deploy-hook "${RELOAD_HOOK}"
    fi
fi

if has_lineage_name "${DOMAIN}-0001" && ! has_lineage_name "${DOMAIN}"; then
    echo "NOTE: An issued certificate exists only as lineage '${DOMAIN}-0001}'. Update nginx ssl_certificate / ssl_certificate_key paths to /etc/letsencrypt/live/${DOMAIN}-0001/... or clear the letsencrypt volume and recreate so the standard name ${DOMAIN} is used." >&2
fi

trap exit TERM
echo "Running periodic certbot renew (every 12h)..."
while true; do
    prune_bad_renewal_configs
    certbot renew --non-interactive
    sleep 12h &
    wait "${!}"
done
