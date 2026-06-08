#!/usr/bin/env bash
# Add a WireGuard peer: sudo bash add_peer.sh <public_key> <preshared_key> <vpn_ip>

set -euo pipefail

PUBLIC_KEY="${1:-}"
PRESHARED_KEY="${2:-}"
VPN_IP="${3:-}"
WG_INTERFACE="${WG_INTERFACE:-wg0}"

if [[ -z "$PUBLIC_KEY" || -z "$PRESHARED_KEY" || -z "$VPN_IP" ]]; then
    echo "[ERROR] Usage: add_peer.sh <public_key> <preshared_key> <vpn_ip>" >&2
    exit 1
fi

if ! [[ "$VPN_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "[ERROR] Invalid VPN IP: $VPN_IP" >&2
    exit 1
fi

# wg set requires a file path for preshared-key, not a string
PSK_FILE=$(mktemp /tmp/wg-psk-XXXXXX)
chmod 600 "$PSK_FILE"
printf '%s' "$PRESHARED_KEY" > "$PSK_FILE"

cleanup() { rm -f "$PSK_FILE"; }
trap cleanup EXIT

if ! wg set "$WG_INTERFACE" \
        peer "$PUBLIC_KEY" \
        preshared-key "$PSK_FILE" \
        allowed-ips "${VPN_IP}/32"; then
    echo "[ERROR] wg set failed for peer $VPN_IP" >&2
    exit 1
fi

if ! wg-quick save "$WG_INTERFACE"; then
    echo "[WARN] wg-quick save failed — peer is active but may not persist after reboot." >&2
fi

echo "[OK] Peer added: ${VPN_IP}"
exit 0
