#!/usr/bin/env bash
# One-shot WireGuard server setup — sudo bash setup_wireguard.sh

set -euo pipefail

# ---- Config ----
WG_INTERFACE="wg0"
WG_PORT="51820"
WG_SUBNET="10.8.0.0/24"
SERVER_IP="10.8.0.1"
WEB_USER="${WEB_USER:-www-data}"          # user that runs Flask

# Detect main network interface
NET_IF=$(ip route | awk '/^default/ {print $5; exit}')

echo "============================================"
echo " WireGuard Server Setup"
echo " Interface : $WG_INTERFACE"
echo " Port      : $WG_PORT"
echo " Subnet    : $WG_SUBNET"
echo " Net iface : $NET_IF"
echo "============================================"
echo ""

if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] Run this script as root (sudo)." >&2
    exit 1
fi

# ---- 1. Install WireGuard ----
echo "[1/7] Installing WireGuard…"
apt-get update -qq
apt-get install -y wireguard wireguard-tools iptables
echo "     Done."

# ---- 2. Generate server keypair ----
echo "[2/7] Generating server keypair…"
SERVER_PRIV=$(wg genkey)
SERVER_PUB=$(echo "$SERVER_PRIV" | wg pubkey)
echo "     Public key: $SERVER_PUB"

# ---- 3. Write wg0.conf ----
echo "[3/7] Writing /etc/wireguard/wg0.conf…"
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address    = ${SERVER_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV}

PostUp = iptables -t nat -A POSTROUTING -s ${WG_SUBNET} -o ${NET_IF} -j MASQUERADE
PostUp = iptables -A FORWARD -i ${WG_INTERFACE} -j ACCEPT
PostUp = iptables -A FORWARD -o ${WG_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT

PostDown = iptables -t nat -D POSTROUTING -s ${WG_SUBNET} -o ${NET_IF} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT
PostDown = iptables -D FORWARD -o ${WG_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT

# Peers are added dynamically by the web application.
EOF

chmod 600 /etc/wireguard/wg0.conf
echo "     Written."

# ---- 4. Enable IP forwarding ----
echo "[4/7] Enabling IP forwarding…"
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -w net.ipv4.ip_forward=1 > /dev/null
echo "     Done."

# ---- 5. Start WireGuard ----
echo "[5/7] Enabling wg-quick@${WG_INTERFACE}…"
systemctl enable --now "wg-quick@${WG_INTERFACE}"
echo "     Done."

# ---- 6. Verify ----
echo "[6/7] Verifying interface…"
wg show "$WG_INTERFACE"

# ---- 7. Sudoers for web app ----
echo "[7/7] Configuring sudoers for $WEB_USER…"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUDOERS_FILE="/etc/sudoers.d/vpn-webapp"

cat > "$SUDOERS_FILE" <<EOF
# Allow Flask app to manage WireGuard peers without a password
${WEB_USER} ALL=(root) NOPASSWD: /usr/bin/wg show ${WG_INTERFACE}
${WEB_USER} ALL=(root) NOPASSWD: /usr/bin/wg show ${WG_INTERFACE} dump
${WEB_USER} ALL=(root) NOPASSWD: /usr/bin/wg set ${WG_INTERFACE} *
${WEB_USER} ALL=(root) NOPASSWD: /usr/sbin/wg-quick save ${WG_INTERFACE}
${WEB_USER} ALL=(root) NOPASSWD: /usr/bin/bash ${SCRIPT_DIR}/add_peer.sh *
${WEB_USER} ALL=(root) NOPASSWD: /usr/bin/bash ${SCRIPT_DIR}/remove_peer.sh *
EOF

chmod 440 "$SUDOERS_FILE"
echo "     Written: $SUDOERS_FILE"

echo ""
echo "============================================"
echo " Setup complete!"
echo ""
echo " Server public key (add to .env):"
echo "   WG_SERVER_PUBLIC_KEY=$SERVER_PUB"
echo ""
echo " Get your server's public IP:"
echo "   curl -s ifconfig.me"
echo ""
echo " Then update .env:"
echo "   WG_SERVER_ENDPOINT=<YOUR_PUBLIC_IP>:${WG_PORT}"
echo "============================================"
