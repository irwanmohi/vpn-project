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

echo "[1/5] Creating log directory $LOG_DIR…"
mkdir -p "$LOG_DIR"
chown www-data:www-data "$LOG_DIR"

echo "[2/5] Installing systemd unit…"
UNIT_FILE="$PROJECT_DIR/scripts/vpn-webapp.service"

sed \
  -e "s|WorkingDirectory=.*|WorkingDirectory=$PROJECT_DIR|" \
  -e "s|EnvironmentFile=.*|EnvironmentFile=$PROJECT_DIR/.env|" \
  -e "s|ExecStart=.*gunicorn|ExecStart=$PROJECT_DIR/venv/bin/gunicorn|" \
  "$UNIT_FILE" > /etc/systemd/system/${SERVICE_NAME}.service

echo "      Written: /etc/systemd/system/${SERVICE_NAME}.service"

echo "[3/5] Enabling WireGuard (wg-quick@wg0)…"
systemctl enable wg-quick@wg0 2>/dev/null || true

echo "[4/5] Enabling MySQL…"
systemctl enable mysql 2>/dev/null || systemctl enable mariadb 2>/dev/null || true

echo "[5/5] Enabling and starting vpn-webapp…"
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

echo ""
echo "All services enabled:"
echo ""
systemctl is-enabled wg-quick@wg0   && echo "  [OK] wg-quick@wg0"
systemctl is-enabled mysql 2>/dev/null || systemctl is-enabled mariadb 2>/dev/null && echo "  [OK] mysql/mariadb"
systemctl is-enabled "$SERVICE_NAME" && echo "  [OK] $SERVICE_NAME (Flask)"
echo ""
systemctl status "$SERVICE_NAME" --no-pager -l | head -20
