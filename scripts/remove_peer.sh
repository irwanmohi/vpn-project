#!/usr/bin/env bash
# Remove a WireGuard peer: sudo bash remove_peer.sh <public_key>

set -euo pipefail

PUBLIC_KEY="${1:-}"
WG_INTERFACE="${WG_INTERFACE:-wg0}"

if [[ -z "$PUBLIC_KEY" ]]; then
    echo "[ERROR] Usage: remove_peer.sh <public_key>" >&2
    exit 1
fi

if ! wg show "$WG_INTERFACE" &>/dev/null; then
    echo "[WARN] WireGuard interface $WG_INTERFACE is not running." >&2
    # Exit 0 so Flask continues deactivating the DB record even if WG is down
    exit 0
fi

if ! wg set "$WG_INTERFACE" peer "$PUBLIC_KEY" remove; then
    echo "[ERROR] Failed to remove peer from $WG_INTERFACE" >&2
    exit 1
fi

if ! wg-quick save "$WG_INTERFACE"; then
    echo "[WARN] wg-quick save failed — peer removed from memory but config may be stale." >&2
fi

echo "[OK] Peer removed."
exit 0
