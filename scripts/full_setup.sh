#!/usr/bin/env bash
# Interactive production installer — sudo bash scripts/full_setup.sh

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────
RED='\033[0;31m';    GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m';   CYAN='\033[0;36m';   BOLD='\033[1m'
DIM='\033[2m';       NC='\033[0m'

# ── Helpers ───────────────────────────────────────────────────
banner()  { echo -e "\n${BOLD}${BLUE}━━━  $*  ━━━${NC}\n"; }
ok()      { echo -e "  ${GREEN}✔${NC}  $*"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $*"; }
err()     { echo -e "  ${RED}✘${NC}  $*" >&2; }
info()    { echo -e "  ${CYAN}→${NC}  $*"; }
ask()     { echo -en "${BOLD}${CYAN}  ?  $1${NC} "; }
sep()     { echo -e "${DIM}  ─────────────────────────────────────────────${NC}"; }

# Auto-detect project root (script lives at <project>/scripts/full_setup.sh)
SRC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Root check ───────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
    err "Please run as root:  sudo bash $0"
    exit 1
fi

# ── OS check ─────────────────────────────────────────────────
if ! command -v apt-get &>/dev/null; then
    err "This script requires a Debian/Ubuntu system (apt-get not found)."
    exit 1
fi

# =============================================================
#  BANNER
# =============================================================
clear
echo -e "${BOLD}${BLUE}"
cat << 'EOF'
 ╔══════════════════════════════════════════════════════╗
 ║       VPN ACCESS MANAGEMENT SYSTEM                  ║
 ║       Production Setup Installer                    ║
 ║       WireGuard · Flask · MySQL · Nginx             ║
 ╚══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo -e " ${DIM}This script will install and configure all required services${NC}"
echo -e " ${DIM}and open the necessary firewall ports for production use.${NC}\n"

# =============================================================
#  PHASE 1 — COLLECT INFORMATION
# =============================================================
banner "PHASE 1 — Configuration"

# ── Domain ───────────────────────────────────────────────────
sep
echo -e "\n ${BOLD}[1/6] Domain Name${NC}"
info "Enter the domain or IP that Nginx will serve."
info "Examples: vpn.example.com  OR  192.168.1.100"
echo ""
while true; do
    ask "Domain / IP address: "
    read -r DOMAIN
    DOMAIN="${DOMAIN// /}"
    if [[ -n "$DOMAIN" ]]; then
        break
    fi
    warn "Domain cannot be empty."
done

# ── Deploy (install) path ────────────────────────────────────
sep
echo -e "\n ${BOLD}[2/5] Deployment Path${NC}"
info "Where should the app be installed (production location)?"
info "Default: /opt/vpn-project"
echo ""
ask "Deploy path [/opt/vpn-project]: "
read -r DEPLOY_PATH
DEPLOY_PATH="${DEPLOY_PATH:-/opt/vpn-project}"
DEPLOY_PATH="${DEPLOY_PATH%/}"

# ── MySQL passwords ──────────────────────────────────────────
sep
echo -e "\n ${BOLD}[3/5] MySQL Passwords${NC}"
echo ""

while true; do
    ask "MySQL root password (new or existing): "
    read -rs MYSQL_ROOT_PASS; echo ""
    [[ -n "$MYSQL_ROOT_PASS" ]] && break
    warn "Password cannot be empty."
done

while true; do
    ask "VPN app DB password (for user 'vpnuser'): "
    read -rs DB_APP_PASS; echo ""
    ask "Confirm VPN app DB password: "
    read -rs DB_APP_PASS2; echo ""
    if [[ "$DB_APP_PASS" == "$DB_APP_PASS2" && -n "$DB_APP_PASS" ]]; then
        break
    fi
    warn "Passwords do not match or are empty. Try again."
done

# ── WireGuard endpoint ───────────────────────────────────────
sep
echo -e "\n ${BOLD}[4/5] WireGuard Server Endpoint${NC}"
info "This is the public IP (or domain) and UDP port that VPN clients connect to."
info "Example: 203.0.113.10:51820"
echo ""

# Auto-detect public IP
DETECTED_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "")
if [[ -n "$DETECTED_IP" ]]; then
    info "Detected public IP: ${BOLD}$DETECTED_IP${NC}"
    ask "WireGuard endpoint [$DETECTED_IP:51820]: "
    read -r WG_ENDPOINT
    WG_ENDPOINT="${WG_ENDPOINT:-$DETECTED_IP:51820}"
else
    ask "WireGuard endpoint (IP:port): "
    read -r WG_ENDPOINT
fi

# ── WireGuard port ───────────────────────────────────────────
WG_PORT=$(echo "$WG_ENDPOINT" | cut -d: -f2)
WG_PORT="${WG_PORT:-51820}"

# ── Flask secret key ─────────────────────────────────────────
sep
echo -e "\n ${BOLD}[5/5] Flask Secret Key${NC}"
info "A random 64-character key will be generated automatically."
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null \
             || openssl rand -hex 32)
ok "Generated: ${DIM}${SECRET_KEY:0:16}…${NC}"

# =============================================================
#  SUMMARY — confirm before proceeding
# =============================================================
banner "INSTALLATION SUMMARY"

echo -e "  ${BOLD}Domain            :${NC} $DOMAIN"
echo -e "  ${BOLD}Source path       :${NC} $SRC_PATH  ${DIM}(auto-detected)${NC}"
echo -e "  ${BOLD}Deploy path       :${NC} $DEPLOY_PATH"
echo -e "  ${BOLD}MySQL root pass   :${NC} ${DIM}(set)${NC}"
echo -e "  ${BOLD}VPN DB user       :${NC} vpnuser / ${DIM}(set)${NC}"
echo -e "  ${BOLD}WireGuard endpoint:${NC} $WG_ENDPOINT"
echo -e "  ${BOLD}WireGuard port    :${NC} $WG_PORT/udp"
echo ""
echo -e "  ${BOLD}Ports to open:${NC}"
echo -e "    22/tcp   — SSH"
echo -e "    80/tcp   — HTTP  (Nginx)"
echo -e "    443/tcp  — HTTPS (Nginx + SSL)"
echo -e "    ${WG_PORT}/udp — WireGuard VPN"
echo ""
ask "Proceed with installation? (y/n) [y]: "
read -r CONFIRM
CONFIRM="${CONFIRM:-y}"
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# =============================================================
#  PHASE 2 — INSTALL PACKAGES
# =============================================================
banner "PHASE 2 — Installing Packages"

info "Setting timezone to Asia/Kuala_Lumpur…"
timedatectl set-timezone Asia/Kuala_Lumpur
ok "Timezone: $(timedatectl show --property=Timezone --value)"

info "Updating package lists…"
apt-get update -qq

info "Installing Nginx, MySQL, Python3, WireGuard, UFW, extras…"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    nginx \
    mysql-server \
    python3 \
    python3-pip \
    python3-venv \
    wireguard \
    wireguard-tools \
    ufw \
    curl \
    dos2unix \
    certbot \
    python3-certbot-nginx \
    iptables \
    net-tools

ok "All packages installed."

# =============================================================
#  PHASE 3 — CONFIGURE MYSQL
# =============================================================
banner "PHASE 3 — Configuring MySQL"

info "Starting MySQL service…"
systemctl start mysql
systemctl enable mysql
ok "MySQL running and enabled."

info "Setting MySQL root password and securing installation…"
mysql --user=root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL
ok "MySQL root secured."

info "Creating database and application user…"
mysql --user=root --password="${MYSQL_ROOT_PASS}" <<SQL
CREATE DATABASE IF NOT EXISTS vpn_system
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'vpnuser'@'localhost'
    IDENTIFIED BY '${DB_APP_PASS}';

GRANT ALL PRIVILEGES ON vpn_system.* TO 'vpnuser'@'localhost';
FLUSH PRIVILEGES;
SQL
ok "Database 'vpn_system' and user 'vpnuser' created."

# Import schema if SQL file exists
SCHEMA_FILE="$SRC_PATH/vpn_system.sql"
if [[ -f "$SCHEMA_FILE" ]]; then
    info "Importing database schema…"
    mysql --user=vpnuser --password="${DB_APP_PASS}" vpn_system < "$SCHEMA_FILE"
    ok "Schema imported."
else
    warn "Schema file not found at $SCHEMA_FILE — import it manually later:"
    warn "  mysql -u vpnuser -p vpn_system < vpn_system.sql"
fi

# =============================================================
#  PHASE 4 — DEPLOY PROJECT FILES
# =============================================================
banner "PHASE 4 — Deploying Project Files"

if [[ "$SRC_PATH" != "$DEPLOY_PATH" ]]; then
    info "Copying project from $SRC_PATH to $DEPLOY_PATH…"
    mkdir -p "$DEPLOY_PATH"
    cp -r "$SRC_PATH"/. "$DEPLOY_PATH/"
    ok "Files copied."
else
    info "Source and deploy paths are the same — skipping copy."
fi

info "Setting ownership to www-data…"
chown -R www-data:www-data "$DEPLOY_PATH"
chmod -R 750 "$DEPLOY_PATH"
ok "Permissions set."

# Fix line endings on shell scripts (important if uploaded from Windows)
info "Fixing script line endings…"
dos2unix "$DEPLOY_PATH"/scripts/*.sh 2>/dev/null || true
chmod +x "$DEPLOY_PATH"/scripts/*.sh
ok "Scripts ready."

# =============================================================
#  PHASE 5 — GENERATE .env FILE
# =============================================================
banner "PHASE 5 — Generating .env"

ENV_FILE="$DEPLOY_PATH/.env"

# We'll fill in WG_SERVER_PUBLIC_KEY after WireGuard setup
cat > "$ENV_FILE" <<ENV
SECRET_KEY=${SECRET_KEY}

MYSQL_HOST=localhost
MYSQL_USER=vpnuser
MYSQL_PASSWORD=${DB_APP_PASS}
MYSQL_DB=vpn_system
MYSQL_PORT=3306

WG_INTERFACE=wg0
WG_SERVER_PUBLIC_KEY=PENDING_WIREGUARD_SETUP
WG_SERVER_ENDPOINT=${WG_ENDPOINT}
WG_DNS=1.1.1.1, 1.0.0.1
WG_CONFIG_PATH=/etc/wireguard/wg0.conf

DEFAULT_EXPIRY_DAYS=7
ENV

chown www-data:www-data "$ENV_FILE"
chmod 640 "$ENV_FILE"
ok ".env written to $ENV_FILE"

# =============================================================
#  PHASE 6 — PYTHON VIRTUAL ENVIRONMENT
# =============================================================
banner "PHASE 6 — Python Virtual Environment"

info "Creating venv at $DEPLOY_PATH/venv…"
python3 -m venv "$DEPLOY_PATH/venv"
ok "venv created."

REQ_FILE="$DEPLOY_PATH/requirements.txt"
if [[ -f "$REQ_FILE" ]]; then
    info "Installing Python dependencies…"
    "$DEPLOY_PATH/venv/bin/pip" install --quiet --upgrade pip
    "$DEPLOY_PATH/venv/bin/pip" install --quiet -r "$REQ_FILE"
    ok "Dependencies installed."
else
    warn "requirements.txt not found — install manually later:"
    warn "  $DEPLOY_PATH/venv/bin/pip install -r $DEPLOY_PATH/requirements.txt"
fi

chown -R www-data:www-data "$DEPLOY_PATH/venv"

# =============================================================
#  PHASE 7 — WIREGUARD SERVER SETUP
# =============================================================
banner "PHASE 7 — WireGuard Setup"

WG_CONF="/etc/wireguard/wg0.conf"

if [[ -f "$WG_CONF" ]]; then
    warn "WireGuard config already exists at $WG_CONF — skipping key generation."
    WG_SERVER_PUB=$(wg show wg0 public-key 2>/dev/null || \
                    grep -oP 'PrivateKey\s*=\s*\K.*' "$WG_CONF" | \
                    wg pubkey 2>/dev/null || echo "UNKNOWN")
else
    info "Generating WireGuard server keypair…"
    WG_SERVER_PRIV=$(wg genkey)
    WG_SERVER_PUB=$(echo "$WG_SERVER_PRIV" | wg pubkey)

    # Detect main outbound interface
    NET_IF=$(ip route | awk '/^default/ {print $5; exit}')

    info "Writing /etc/wireguard/wg0.conf…"
    cat > "$WG_CONF" <<WG
[Interface]
Address    = 10.8.0.1/24
ListenPort = ${WG_PORT}
PrivateKey = ${WG_SERVER_PRIV}

PostUp   = iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o ${NET_IF} -j MASQUERADE; \\
           iptables -A FORWARD -i wg0 -j ACCEPT; \\
           iptables -A FORWARD -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

PostDown = iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o ${NET_IF} -j MASQUERADE; \\
           iptables -D FORWARD -i wg0 -j ACCEPT; \\
           iptables -D FORWARD -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Peers are added dynamically by the web application.
WG
    chmod 600 "$WG_CONF"
    ok "wg0.conf written."

    info "Enabling IP forwarding…"
    grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf \
        || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    ok "IP forwarding enabled."
fi

info "Enabling wg-quick@wg0 service…"
systemctl enable --now wg-quick@wg0
ok "WireGuard running."

# Patch .env with real public key
sed -i "s|WG_SERVER_PUBLIC_KEY=.*|WG_SERVER_PUBLIC_KEY=${WG_SERVER_PUB}|" "$ENV_FILE"
ok "WG_SERVER_PUBLIC_KEY updated in .env"

# Configure sudoers for Flask app
info "Configuring sudoers for www-data…"
SUDOERS_FILE="/etc/sudoers.d/vpn-webapp"
cat > "$SUDOERS_FILE" <<SUDO
# Allow Flask app to manage WireGuard peers without a password
www-data ALL=(root) NOPASSWD: /usr/bin/wg show wg0
www-data ALL=(root) NOPASSWD: /usr/bin/wg show wg0 dump
www-data ALL=(root) NOPASSWD: /usr/bin/wg set wg0 *
www-data ALL=(root) NOPASSWD: /usr/sbin/wg-quick save wg0
www-data ALL=(root) NOPASSWD: /usr/bin/bash ${DEPLOY_PATH}/scripts/add_peer.sh *
www-data ALL=(root) NOPASSWD: /usr/bin/bash ${DEPLOY_PATH}/scripts/remove_peer.sh *
SUDO
chmod 440 "$SUDOERS_FILE"
ok "sudoers configured."

# =============================================================
#  PHASE 8 — CONFIGURE NGINX
# =============================================================
banner "PHASE 8 — Configuring Nginx"

NGINX_SITE="/etc/nginx/sites-available/vpn-manager"
NGINX_ENABLED="/etc/nginx/sites-enabled/vpn-manager"

info "Writing Nginx config for domain: ${BOLD}$DOMAIN${NC}"
cat > "$NGINX_SITE" <<NGINX
# ── VPN Management System ──────────────────────────────────
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    # Security headers
    add_header X-Frame-Options        "SAMEORIGIN"   always;
    add_header X-Content-Type-Options "nosniff"      always;
    add_header X-XSS-Protection       "1; mode=block" always;
    add_header Referrer-Policy        "strict-origin-when-cross-origin" always;

    # Max upload size (for config files)
    client_max_body_size 5M;

    # Proxy to Gunicorn
    location / {
        proxy_pass         http://127.0.0.1:5000;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
        proxy_connect_timeout 10s;
    }

    # Static files served directly by Nginx (faster)
    location /static/ {
        alias ${DEPLOY_PATH}/static/;
        expires 7d;
        add_header Cache-Control "public, immutable";
    }

    # Block access to hidden files (.env etc.)
    location ~ /\. {
        deny all;
        return 404;
    }
}
NGINX

# Enable site
ln -sf "$NGINX_SITE" "$NGINX_ENABLED"

# Remove default site if it exists
rm -f /etc/nginx/sites-enabled/default

# Test config
if nginx -t 2>/dev/null; then
    ok "Nginx config valid."
else
    err "Nginx config test failed. Check $NGINX_SITE"
    nginx -t
fi

info "Starting and enabling Nginx…"
systemctl enable --now nginx
systemctl reload nginx
ok "Nginx running."

# =============================================================
#  PHASE 9 — CONFIGURE FIREWALL (UFW)
# =============================================================
banner "PHASE 9 — Firewall (UFW)"

info "Configuring UFW rules…"

# Reset to clean state (non-interactive)
ufw --force reset > /dev/null

# Default policies
ufw default deny incoming  > /dev/null
ufw default allow outgoing > /dev/null

# Allow required ports
ufw allow 22/tcp    comment 'SSH'            > /dev/null
ufw allow 80/tcp    comment 'HTTP (Nginx)'   > /dev/null
ufw allow 443/tcp   comment 'HTTPS (Nginx)'  > /dev/null
ufw allow "${WG_PORT}/udp" comment 'WireGuard VPN' > /dev/null

# Enable UFW
ufw --force enable > /dev/null

ok "Firewall configured. Active rules:"
echo ""
ufw status numbered | grep -v "^$" | sed 's/^/    /'
echo ""

# =============================================================
#  PHASE 10 — SYSTEMD SERVICE
# =============================================================
banner "PHASE 10 — Systemd Auto-Start"

LOG_DIR="/var/log/vpn-webapp"
mkdir -p "$LOG_DIR"
chown www-data:www-data "$LOG_DIR"

UNIT_SRC="$DEPLOY_PATH/scripts/vpn-webapp.service"
UNIT_DST="/etc/systemd/system/vpn-webapp.service"

if [[ -f "$UNIT_SRC" ]]; then
    # Patch paths in service file
    sed \
        -e "s|WorkingDirectory=.*|WorkingDirectory=${DEPLOY_PATH}|" \
        -e "s|EnvironmentFile=.*|EnvironmentFile=${DEPLOY_PATH}/.env|" \
        -e "s|ExecStart=.*gunicorn|ExecStart=${DEPLOY_PATH}/venv/bin/gunicorn|" \
        "$UNIT_SRC" > "$UNIT_DST"
    ok "Service unit installed."
else
    # Write service file inline
    info "Writing systemd unit from template…"
    cat > "$UNIT_DST" <<UNIT
[Unit]
Description=VPN Access Management System (Gunicorn)
After=network.target mysql.service
Wants=mysql.service

[Service]
User=www-data
Group=www-data
WorkingDirectory=${DEPLOY_PATH}
EnvironmentFile=${DEPLOY_PATH}/.env
ExecStart=${DEPLOY_PATH}/venv/bin/gunicorn \\
          --workers 4 \\
          --bind 127.0.0.1:5000 \\
          --timeout 120 \\
          --access-logfile ${LOG_DIR}/access.log \\
          --error-logfile  ${LOG_DIR}/error.log \\
          "app:create_app()"
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=on-failure
RestartSec=5s
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT
    ok "Service unit written."
fi

systemctl daemon-reload
systemctl enable vpn-webapp
ok "vpn-webapp enabled for auto-start."

info "Attempting to start vpn-webapp…"
if systemctl start vpn-webapp 2>/dev/null; then
    ok "vpn-webapp started."
else
    warn "vpn-webapp could not start yet — likely because admin account not created."
    warn "Create it first:  sudo -u www-data bash -c 'cd ${DEPLOY_PATH} && venv/bin/python create_admin.py'"
fi

# =============================================================
#  PHASE 11 — CRON JOB
# =============================================================
banner "PHASE 11 — Cron Job (Auto-Expire)"

CRON_FILE="/etc/cron.d/vpn-manager"

cat > "$CRON_FILE" <<CRON
# VPN Manager cron jobs
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/5 * * * * root bash ${DEPLOY_PATH}/scripts/cron_expiry.sh >> /var/log/vpn_expiry.log 2>&1
* * * * * root bash ${DEPLOY_PATH}/scripts/cron_monitor.sh >> /var/log/vpn_monitor.log 2>&1
0 8 * * * root ${DEPLOY_PATH}/venv/bin/python ${DEPLOY_PATH}/scripts/notify_expiry.py >> /var/log/vpn_notify.log 2>&1
0 3 * * * root bash ${DEPLOY_PATH}/scripts/backup_db.sh >> /var/log/vpn_backup.log 2>&1
CRON

chmod 644 "$CRON_FILE"
ok "Cron jobs installed at $CRON_FILE"

# =============================================================
#  FINAL SUMMARY
# =============================================================
banner "INSTALLATION COMPLETE"

echo -e "${BOLD}${GREEN}"
cat << 'EOF'
  ╔══════════════════════════════════════════════════════╗
  ║              SETUP SUCCESSFUL                        ║
  ╚══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e " ${BOLD}── Service Status ────────────────────────────────────${NC}"
for svc in mysql wg-quick@wg0 nginx vpn-webapp; do
    STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
    if [[ "$STATUS" == "active" ]]; then
        echo -e "   ${GREEN}✔${NC}  $svc  ${DIM}(active)${NC}"
    else
        echo -e "   ${YELLOW}⚠${NC}  $svc  ${DIM}($STATUS)${NC}"
    fi
done

echo ""
echo -e " ${BOLD}── Open Ports ────────────────────────────────────────${NC}"
echo -e "   22/tcp    SSH"
echo -e "   80/tcp    HTTP  — http://${DOMAIN}"
echo -e "   443/tcp   HTTPS — https://${DOMAIN}  (after SSL setup)"
echo -e "   ${WG_PORT}/udp   WireGuard VPN"

echo ""
echo -e " ${BOLD}── Configuration Files ──────────────────────────────${NC}"
echo -e "   ${DIM}Project  :${NC} ${DEPLOY_PATH}"
echo -e "   ${DIM}.env     :${NC} ${DEPLOY_PATH}/.env"
echo -e "   ${DIM}Nginx    :${NC} /etc/nginx/sites-available/vpn-manager"
echo -e "   ${DIM}WireGuard:${NC} /etc/wireguard/wg0.conf"
echo -e "   ${DIM}Systemd  :${NC} /etc/systemd/system/vpn-webapp.service"
echo -e "   ${DIM}Logs     :${NC} /var/log/vpn-webapp/"

echo ""
echo -e " ${BOLD}── WireGuard Server Public Key ──────────────────────${NC}"
echo -e "   ${CYAN}${WG_SERVER_PUB}${NC}"
echo -e "   ${DIM}(Already saved to ${DEPLOY_PATH}/.env)${NC}"

echo ""
echo -e " ${BOLD}── Next Steps ───────────────────────────────────────${NC}"

STEP=1

if ! systemctl is-active vpn-webapp &>/dev/null; then
echo -e ""
echo -e "   ${BOLD}${STEP}.${NC} Create admin account:"
echo -e "      ${CYAN}cd ${DEPLOY_PATH} && sudo venv/bin/python create_admin.py${NC}"
STEP=$((STEP+1))
fi

echo -e ""
echo -e "   ${BOLD}${STEP}.${NC} Add HTTPS with Let's Encrypt (recommended, interactive):"
echo -e "      ${CYAN}sudo bash ${DEPLOY_PATH}/scripts/setup_https.sh${NC}"
STEP=$((STEP+1))

echo -e ""
echo -e "   ${BOLD}${STEP}.${NC} (Optional) Local GeoLite2 geolocation — no API rate limit (interactive):"
echo -e "      ${DIM}Free signup: https://www.maxmind.com/en/geolite2/signup${NC}"
echo -e "      ${CYAN}sudo bash ${DEPLOY_PATH}/scripts/setup_geoip.sh${NC}"
STEP=$((STEP+1))

echo -e ""
echo -e "   ${BOLD}${STEP}.${NC} Verify all services survive a reboot:"
echo -e "      ${CYAN}sudo reboot${NC}"
echo -e "      ${CYAN}sudo systemctl is-active vpn-webapp wg-quick@wg0 mysql nginx${NC}"
STEP=$((STEP+1))

echo -e ""
echo -e "   ${BOLD}${STEP}.${NC} Monitor Flask app logs:"
echo -e "      ${CYAN}sudo journalctl -u vpn-webapp -f${NC}"
echo -e "      ${CYAN}sudo tail -f /var/log/vpn-webapp/error.log${NC}"

echo -e ""
echo -e " ${BOLD}── Your application ─────────────────────────────────${NC}"
echo -e "   ${BOLD}${GREEN}http://${DOMAIN}${NC}"
echo ""
echo -e "${DIM}  Run 'sudo systemctl status vpn-webapp' if anything looks wrong.${NC}"
echo ""
