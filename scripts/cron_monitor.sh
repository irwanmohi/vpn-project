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

CONNECTED_THRESHOLD=180
DISCONNECTED_THRESHOLD=300

NOW=$(date +%s)

PEERS=$($MYSQL_CMD <<'SQL'
    SELECT vp.public_key, vp.vpn_ip, vp.user_id
    FROM vpn_peers vp
    JOIN users u ON vp.user_id = u.id
    WHERE vp.is_active = 1 AND u.is_active = 1
SQL
)

[[ -z "$PEERS" ]] && exit 0

WG_DUMP=$(wg show "$WG_IFACE" dump 2>/dev/null || true)
[[ -z "$WG_DUMP" ]] && exit 0

_geolocate() {
    local ip="$1"
    # Private / loopback — no external lookup needed
    if [[ "$ip" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.|::1$) ]]; then
        echo "Local|Local|0|0"
        return
    fi
    local geo
    geo=$(curl -s --max-time 5 "http://ip-api.com/json/${ip}?fields=status,country,city,lat,lon" 2>/dev/null || echo '{}')
    local status
    status=$(echo "$geo" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
    if [[ "$status" == "success" ]]; then
        local country city lat lon
        country=$(echo "$geo" | sed -n 's/.*"country":"\([^"]*\)".*/\1/p')
        city=$(echo "$geo"    | sed -n 's/.*"city":"\([^"]*\)".*/\1/p')
        lat=$(echo "$geo"     | sed -n 's/.*"lat":\([^,}]*\).*/\1/p' | tr -d ' ')
        lon=$(echo "$geo"     | sed -n 's/.*"lon":\([^,}]*\).*/\1/p' | tr -d ' ')
        echo "${country}|${city}|${lat:-0}|${lon:-0}"
    else
        echo "Unknown|Unknown|0|0"
    fi
}

while IFS=$'\t' read -r PUBLIC_KEY VPN_IP USER_ID; do

    LAST_HS=$(echo "$WG_DUMP" | awk -v key="$PUBLIC_KEY" '$1==key {print $5}')

    [[ -z "$LAST_HS" || "$LAST_HS" == "0" ]] && continue

    AGE=$(( NOW - LAST_HS ))

    LAST_EVENT=$($MYSQL_CMD <<SQL
        SELECT event_type FROM connection_logs
        WHERE user_id = $USER_ID AND vpn_ip = '$VPN_IP'
          AND event_type IN ('connect','disconnect','revoked','expired')
        ORDER BY event_time DESC LIMIT 1
SQL
    )

    if [[ $AGE -lt $CONNECTED_THRESHOLD ]]; then
        if [[ "$LAST_EVENT" != "connect" ]]; then

            # Extract real client IP from wg dump endpoint field (col 3: IP:port or [IPv6]:port)
            ENDPOINT=$(echo "$WG_DUMP" | awk -v key="$PUBLIC_KEY" '$1==key {print $3}')
            REAL_IP=""
            if [[ -n "$ENDPOINT" && "$ENDPOINT" != "(none)" ]]; then
                if [[ "$ENDPOINT" == \[* ]]; then
                    REAL_IP=$(echo "$ENDPOINT" | sed 's/^\[\(.*\)\]:.*/\1/')
                else
                    REAL_IP="${ENDPOINT%:*}"
                fi
            fi

            COUNTRY="Unknown" CITY="Unknown" LAT="0" LON="0"
            if [[ -n "$REAL_IP" ]]; then
                GEO=$(_geolocate "$REAL_IP")
                IFS='|' read -r COUNTRY CITY LAT LON <<< "$GEO"
                [[ -z "$LAT" ]] && LAT="0"
                [[ -z "$LON" ]] && LON="0"
                COUNTRY=$(echo "$COUNTRY" | sed "s/'/''/g")
                CITY=$(echo "$CITY"       | sed "s/'/''/g")
            fi

            REAL_IP_SQL="NULL"
            [[ -n "$REAL_IP" ]] && REAL_IP_SQL="'$REAL_IP'"

            $MYSQL_CMD <<SQL
                INSERT INTO connection_logs
                    (user_id, vpn_ip, event_type, real_ip, country, city, latitude, longitude)
                VALUES
                    ($USER_ID, '$VPN_IP', 'connect', $REAL_IP_SQL, '$COUNTRY', '$CITY', $LAT, $LON);
SQL
        fi

    elif [[ $AGE -gt $DISCONNECTED_THRESHOLD ]]; then
        if [[ "$LAST_EVENT" == "connect" ]]; then
            $MYSQL_CMD <<SQL
                INSERT INTO connection_logs (user_id, vpn_ip, event_type)
                VALUES ($USER_ID, '$VPN_IP', 'disconnect');
SQL
        fi
    fi

done <<< "$PEERS"

exit 0
