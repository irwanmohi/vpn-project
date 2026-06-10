#!/usr/bin/env bash
# Auto-revoke expired VPN users — run every 5 min via cron

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REMOVE_PEER="$SCRIPT_DIR/remove_peer.sh"

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

# Pass credentials via defaults file, not command line (hides from ps / logs)
MYSQL_DEFAULTS=$(mktemp)
chmod 600 "$MYSQL_DEFAULTS"
cat > "$MYSQL_DEFAULTS" <<EOF
[client]
host=$DB_HOST
user=$DB_USER
password=$DB_PASS
EOF
trap 'rm -f "$MYSQL_DEFAULTS"' EXIT

MYSQL_CMD="mysql --defaults-extra-file=$MYSQL_DEFAULTS $DB_NAME -N -s"

echo "VPN Expiry Check — $(date '+%Y-%m-%d %H:%M:%S')"

EXPIRED=$($MYSQL_CMD <<'SQL'
    SELECT
        vp.public_key,
        vp.vpn_ip,
        vp.id         AS peer_id,
        u.id          AS user_id,
        u.username
    FROM vpn_peers vp
    JOIN users u ON vp.user_id = u.id
    WHERE vp.is_active = 1
      AND (u.expires_at < NOW() OR u.is_active = 0)
SQL
)

if [[ -z "$EXPIRED" ]]; then
    echo "[OK] No expired peers to remove."
    exit 0
fi

COUNT=0

while IFS=$'\t' read -r PUBLIC_KEY VPN_IP PEER_ID USER_ID USERNAME; do

    echo ""
    echo "→ Expiring: $USERNAME (peer $VPN_IP)"

    if bash "$REMOVE_PEER" "$PUBLIC_KEY"; then
        echo "  [WG] Peer removed from interface."
    else
        echo "  [WG] WARN: Could not remove peer — may already be gone."
    fi

    $MYSQL_CMD <<SQL
        START TRANSACTION;

        UPDATE vpn_peers
           SET is_active = 0
         WHERE id = $PEER_ID;

        UPDATE users
           SET is_active = 0
         WHERE id = $USER_ID;

        UPDATE ip_pool
           SET is_allocated = 0,
               allocated_to = NULL,
               allocated_at = NULL
         WHERE ip_address = '$VPN_IP';

        INSERT INTO connection_logs
            (user_id, vpn_ip, event_type, notes)
        VALUES
            ($USER_ID, '$VPN_IP', 'expired', 'Auto-expired by cron');

        COMMIT;
SQL

    echo "  [DB] Records updated."
    COUNT=$((COUNT + 1))

done <<< "$EXPIRED"

echo ""
echo "[DONE] Expired $COUNT peer(s)."
exit 0
