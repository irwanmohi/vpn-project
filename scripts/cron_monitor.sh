#!/usr/bin/env bash
# Detect VPN connect/disconnect events by polling wg show every minute

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

ENV_FILE="$PROJECT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source <(grep -E '^[A-Z_]+=' "$ENV_FILE" | sed "s/=\(.*\)/='\1'/")
fi

DB_HOST="${MYSQL_HOST:-localhost}"
DB_USER="${MYSQL_USER:-vpnuser}"
DB_PASS="${MYSQL_PASSWORD:-vpnpassword}"
DB_NAME="${MYSQL_DB:-vpn_system}"
WG_IFACE="${WG_INTERFACE:-wg0}"

MYSQL_CMD="mysql -h $DB_HOST -u $DB_USER -p${DB_PASS} $DB_NAME -N -s"

# WireGuard handshake is every ~2 min when active.
# If last_handshake < 3 min ago → peer is connected.
CONNECTED_THRESHOLD=180
# If last_handshake > 5 min ago → peer has disconnected.
DISCONNECTED_THRESHOLD=300

NOW=$(date +%s)

# Get all active peers from DB
PEERS=$($MYSQL_CMD <<'SQL'
    SELECT vp.public_key, vp.vpn_ip, vp.user_id
    FROM vpn_peers vp
    JOIN users u ON vp.user_id = u.id
    WHERE vp.is_active = 1 AND u.is_active = 1
SQL
)

[[ -z "$PEERS" ]] && exit 0

# Get live handshake times from WireGuard
WG_DUMP=$(wg show "$WG_IFACE" dump 2>/dev/null || true)
[[ -z "$WG_DUMP" ]] && exit 0

while IFS=$'\t' read -r PUBLIC_KEY VPN_IP USER_ID; do

    # Find last_handshake for this peer in wg dump (column 5, 0-indexed)
    LAST_HS=$(echo "$WG_DUMP" | awk -v key="$PUBLIC_KEY" '$1==key {print $5}')

    [[ -z "$LAST_HS" || "$LAST_HS" == "0" ]] && continue

    AGE=$(( NOW - LAST_HS ))

    # Check last logged event for this peer
    LAST_EVENT=$($MYSQL_CMD <<SQL
        SELECT event_type FROM connection_logs
        WHERE user_id = $USER_ID AND vpn_ip = '$VPN_IP'
          AND event_type IN ('connect','disconnect','revoked','expired')
        ORDER BY event_time DESC LIMIT 1
SQL
    )

    if [[ $AGE -lt $CONNECTED_THRESHOLD ]]; then
        # Peer is active — log connect if not already connected
        if [[ "$LAST_EVENT" != "connect" ]]; then
            $MYSQL_CMD <<SQL
                INSERT INTO connection_logs (user_id, vpn_ip, event_type)
                VALUES ($USER_ID, '$VPN_IP', 'connect');
SQL
        fi
    elif [[ $AGE -gt $DISCONNECTED_THRESHOLD ]]; then
        # Peer went quiet — log disconnect if was connected
        if [[ "$LAST_EVENT" == "connect" ]]; then
            $MYSQL_CMD <<SQL
                INSERT INTO connection_logs (user_id, vpn_ip, event_type)
                VALUES ($USER_ID, '$VPN_IP', 'disconnect');
SQL
        fi
    fi

done <<< "$PEERS"

exit 0
