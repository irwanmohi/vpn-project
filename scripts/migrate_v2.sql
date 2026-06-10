-- Migration v2: traffic counters + login rate limiting
-- Run once on existing installs:
--   mysql -u vpnuser -p vpn_system < scripts/migrate_v2.sql

ALTER TABLE vpn_peers
    ADD COLUMN total_rx BIGINT DEFAULT 0,
    ADD COLUMN total_tx BIGINT DEFAULT 0,
    ADD COLUMN last_rx  BIGINT DEFAULT 0,
    ADD COLUMN last_tx  BIGINT DEFAULT 0;

ALTER TABLE users
    ADD COLUMN expiry_notified TINYINT(1) DEFAULT 0;

CREATE TABLE IF NOT EXISTS failed_logins (
    id           INT          AUTO_INCREMENT PRIMARY KEY,
    username     VARCHAR(100) NOT NULL,
    ip_address   VARCHAR(45)  NOT NULL,
    attempted_at TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    KEY idx_failed_user_time (username, attempted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
