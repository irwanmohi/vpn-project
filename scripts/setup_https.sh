#!/usr/bin/env bash
# Enable HTTPS via Let's Encrypt on the existing nginx site.
#
# Interactive:      sudo bash setup_https.sh
# Non-interactive:  sudo bash setup_https.sh <domain> [email]

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0"
    exit 1
fi

DOMAIN="${1:-}"
EMAIL="${2:-}"

echo "=============================================="
echo "  HTTPS Setup — Let's Encrypt"
echo "=============================================="
echo ""

if [[ -z "$DOMAIN" ]]; then
    # Suggest the domain already configured in nginx, if any
    DETECTED=$(grep -rhoP 'server_name\s+\K[^;]+' /etc/nginx/sites-enabled/ 2>/dev/null | head -1 | xargs || true)
    if [[ -n "$DETECTED" && "$DETECTED" != "_" ]]; then
        read -rp "? Domain name [$DETECTED]: " DOMAIN
        DOMAIN="${DOMAIN:-$DETECTED}"
    else
        read -rp "? Domain name (e.g. vpn.example.com): " DOMAIN
    fi
fi

if [[ -z "$DOMAIN" ]]; then
    echo "[ERROR] Domain is required."
    exit 1
fi

if [[ -z "$EMAIL" ]]; then
    read -rp "? Email for renewal notices (Enter to skip): " EMAIL
fi

echo ""
echo "  Domain : $DOMAIN"
echo "  Email  : ${EMAIL:-<none>}"
echo ""
read -rp "Proceed? [Y/n]: " CONFIRM
[[ "${CONFIRM,,}" == "n" ]] && { echo "Cancelled."; exit 0; }

if ! command -v certbot >/dev/null; then
    echo "Installing certbot…"
    apt-get update -qq
    apt-get install -y -qq certbot python3-certbot-nginx
fi

echo "Requesting certificate for $DOMAIN…"
if [[ -n "$EMAIL" ]]; then
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect
else
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect
fi

nginx -t && systemctl reload nginx

systemctl enable --now certbot.timer 2>/dev/null || true

echo ""
echo "[OK] HTTPS enabled — https://$DOMAIN"
echo "[OK] HTTP now redirects to HTTPS."
echo "[OK] Auto-renewal enabled via certbot.timer:"
systemctl list-timers certbot.timer --no-pager | head -3 || true
