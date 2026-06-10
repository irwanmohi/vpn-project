#!/usr/bin/env bash
# Enable HTTPS via Let's Encrypt on the existing nginx site.
# Usage: sudo bash setup_https.sh <domain> [email]
# Example: sudo bash setup_https.sh mimtech.dpdns.org admin@example.com

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0 <domain> [email]"
    exit 1
fi

DOMAIN="${1:-}"
EMAIL="${2:-}"

if [[ -z "$DOMAIN" ]]; then
    echo "Usage: sudo bash $0 <domain> [email]"
    exit 1
fi

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

echo ""
echo "[OK] HTTPS enabled — https://$DOMAIN"
echo "[OK] HTTP now redirects to HTTPS."
echo "[OK] Auto-renewal handled by certbot.timer:"
systemctl list-timers certbot.timer --no-pager | head -3 || true
