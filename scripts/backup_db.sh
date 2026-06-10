#!/usr/bin/env bash
# Daily MySQL backup — keeps the last 7 days. Run via cron.

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

BACKUP_DIR="/var/backups/vpn-manager"
KEEP_DAYS=7

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

MYSQL_DEFAULTS=$(mktemp)
chmod 600 "$MYSQL_DEFAULTS"
cat > "$MYSQL_DEFAULTS" <<EOF
[client]
host=$DB_HOST
user=$DB_USER
password=$DB_PASS
EOF
trap 'rm -f "$MYSQL_DEFAULTS"' EXIT

STAMP=$(date '+%Y-%m-%d')
OUTFILE="$BACKUP_DIR/${DB_NAME}_${STAMP}.sql.gz"

mysqldump --defaults-extra-file="$MYSQL_DEFAULTS" \
    --single-transaction --quick --routines "$DB_NAME" | gzip > "$OUTFILE"

chmod 600 "$OUTFILE"
echo "[OK] Backup written: $OUTFILE ($(du -h "$OUTFILE" | cut -f1))"

find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -mtime +"$KEEP_DAYS" -delete
echo "[OK] Pruned backups older than $KEEP_DAYS days."
