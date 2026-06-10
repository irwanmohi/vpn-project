#!/usr/bin/env bash
# Install MaxMind GeoLite2 local database + weekly auto-update.
# Usage: sudo bash setup_geoip.sh <account_id> <license_key>
#
# Get free credentials at https://www.maxmind.com/en/geolite2/signup
# NOTE: never commit your license key to git — it lives only in /etc/GeoIP.conf

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0 <account_id> <license_key>"
    exit 1
fi

ACCOUNT_ID="${1:-}"
LICENSE_KEY="${2:-}"

if [[ -z "$ACCOUNT_ID" || -z "$LICENSE_KEY" ]]; then
    echo "Usage: sudo bash $0 <account_id> <license_key>"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "[1/4] Installing geoipupdate…"
apt-get update -qq
apt-get install -y -qq geoipupdate

echo "[2/4] Writing /etc/GeoIP.conf…"
cat > /etc/GeoIP.conf <<EOF
AccountID $ACCOUNT_ID
LicenseKey $LICENSE_KEY
EditionIDs GeoLite2-ASN GeoLite2-City GeoLite2-Country
EOF
chmod 600 /etc/GeoIP.conf

echo "[3/4] Downloading GeoLite2 databases (first run)…"
geoipupdate -v

echo "[4/4] Scheduling twice-weekly database updates…"
cat > /etc/cron.d/geoipupdate <<'EOF'
# MaxMind GeoLite2 database update (Wed & Sat 04:30)
30 4 * * 3,6 root /usr/bin/geoipupdate
EOF
chmod 644 /etc/cron.d/geoipupdate

if [[ -x "$PROJECT_DIR/venv/bin/pip" ]]; then
    echo "Installing geoip2 Python library in venv…"
    "$PROJECT_DIR/venv/bin/pip" install -q geoip2
fi

echo ""
echo "[OK] GeoLite2 databases installed:"
ls -lh /var/lib/GeoIP/*.mmdb
echo ""
echo "[OK] The app now uses the local database automatically"
echo "     (services/geolocation.py checks /var/lib/GeoIP/GeoLite2-City.mmdb)."
echo "     Restart the app to pick it up:  systemctl restart vpn-webapp"
