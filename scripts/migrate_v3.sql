-- Migration v3: extension requests (user self-service renewal workflow)
-- Run once on existing installs:
--   mysql -u vpnuser -p vpn_system < scripts/migrate_v3.sql

CREATE TABLE IF NOT EXISTS extension_requests (
    id           INT       AUTO_INCREMENT PRIMARY KEY,
    user_id      INT       NOT NULL,
    status       ENUM('pending','approved','rejected') DEFAULT 'pending',
    requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at  TIMESTAMP NULL DEFAULT NULL,
    resolved_by  INT       NULL,
    days_granted INT       NULL,
    KEY idx_ext_user   (user_id),
    KEY idx_ext_status (status),
    CONSTRAINT fk_ext_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
