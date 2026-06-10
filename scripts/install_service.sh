#!/usr/bin/env bash
# Register all services to auto-start: sudo bash scripts/install_service.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_NAME="vpn-webapp"
LOG_DIR="/var/log/vpn-webapp"

echo "VPN Manager — Service Setup (project: $PROJECT_DIR)"
echo ""

if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Run as root: sudo bash $0" >&2
    exit 1
fi

echo "[1/6] Creating log directory $LOG_DIR…"
mkdir -p "$LOG_DIR"
chown root:root "$LOG_DIR"

echo "[2/6] Installing systemd unit…"
UNIT_FILE="$PROJECT_DIR/scripts/vpn-webapp.service"

sed \
  -e "s|WorkingDirectory=.*|WorkingDirectory=$PROJECT_DIR|" \
  -e "s|EnvironmentFile=.*|EnvironmentFile=$PROJECT_DIR/.env|" \
  -e "s|ExecStart=.*gunicorn|ExecStart=$PROJECT_DIR/venv/bin/gunicorn|" \
  "$UNIT_FILE" > /etc/systemd/system/${SERVICE_NAME}.service

echo "      Written: /etc/systemd/system/${SERVICE_NAME}.service"

echo "[3/6] Enabling WireGuard (wg-quick@wg0)…"
systemctl enable wg-quick@wg0 2>/dev/null || true

echo "[4/6] Enabling MySQL…"
systemctl enable mysql 2>/dev/null || systemctl enable mariadb 2>/dev/null || true

echo "[5/6] Enabling and starting vpn-webapp…"
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

echo "[6/6] Enabling SSL auto-renewal (certbot.timer)…"
if systemctl list-unit-files certbot.timer >/dev/null 2>&1; then
    systemctl enable --now certbot.timer 2>/dev/null || true
    echo "      certbot.timer enabled — certificates renew automatically."
else
    echo "      certbot not installed — skip (run setup_https.sh first if you need SSL)."
fi

echo ""
echo "All services enabled:"
echo ""
systemctl is-enabled wg-quick@wg0   && echo "  [OK] wg-quick@wg0"
systemctl is-enabled mysql 2>/dev/null || systemctl is-enabled mariadb 2>/dev/null && echo "  [OK] mysql/mariadb"
systemctl is-enabled "$SERVICE_NAME" && echo "  [OK] $SERVICE_NAME (Flask)"
systemctl is-enabled certbot.timer 2>/dev/null && echo "  [OK] certbot.timer (SSL auto-renew)"
echo ""
systemctl status "$SERVICE_NAME" --no-pager -l | head -20
