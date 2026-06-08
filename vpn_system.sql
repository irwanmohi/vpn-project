-- =============================================================
-- Automated VPN Access Management System
-- Database Schema — MySQL 8.0+
-- =============================================================

CREATE DATABASE IF NOT EXISTS vpn_system
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE vpn_system;

-- -----------------------------------------------------------
-- Admins
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS admins (
    id            INT          AUTO_INCREMENT PRIMARY KEY,
    username      VARCHAR(50)  NOT NULL,
    email         VARCHAR(100) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    last_login    TIMESTAMP    NULL,
    UNIQUE KEY uq_admins_username (username),
    UNIQUE KEY uq_admins_email    (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -----------------------------------------------------------
-- Users  (VPN subscribers)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id            INT          AUTO_INCREMENT PRIMARY KEY,
    username      VARCHAR(50)  NOT NULL,
    email         VARCHAR(100) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name     VARCHAR(100) DEFAULT '',
    created_at    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    expires_at    TIMESTAMP    NOT NULL,
    is_active     TINYINT(1)   DEFAULT 1,
    created_by    INT          NULL COMMENT 'admin id who created this user',
    UNIQUE KEY uq_users_username (username),
    UNIQUE KEY uq_users_email    (email),
    KEY idx_users_is_active  (is_active),
    KEY idx_users_expires_at (expires_at),
    CONSTRAINT fk_users_admin FOREIGN KEY (created_by)
        REFERENCES admins(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -----------------------------------------------------------
-- VPN Peers  (one active peer per user at most)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS vpn_peers (
    id                INT          AUTO_INCREMENT PRIMARY KEY,
    user_id           INT          NOT NULL,
    private_key       TEXT         NOT NULL,
    public_key        TEXT         NOT NULL,
    preshared_key     TEXT         NOT NULL,
    vpn_ip            VARCHAR(20)  NOT NULL,
    dns               VARCHAR(100) DEFAULT '1.1.1.1, 1.0.0.1',
    server_endpoint   VARCHAR(150) NOT NULL,
    server_public_key TEXT         NOT NULL,
    allowed_ips       VARCHAR(100) DEFAULT '0.0.0.0/0, ::/0',
    created_at        TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    is_active         TINYINT(1)   DEFAULT 1,
    config_downloaded TINYINT(1)   DEFAULT 0,
    UNIQUE KEY uq_peers_vpn_ip (vpn_ip),
    KEY idx_peers_user_id   (user_id),
    KEY idx_peers_is_active (is_active),
    CONSTRAINT fk_peers_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -----------------------------------------------------------
-- Connection / Activity Logs
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS connection_logs (
    id             INT          AUTO_INCREMENT PRIMARY KEY,
    user_id        INT          NOT NULL,
    vpn_ip         VARCHAR(20)  DEFAULT NULL,
    real_ip        VARCHAR(45)  DEFAULT NULL,
    country        VARCHAR(100) DEFAULT 'Unknown',
    city           VARCHAR(100) DEFAULT 'Unknown',
    latitude       DOUBLE       DEFAULT 0,
    longitude      DOUBLE       DEFAULT 0,
    event_type     ENUM(
                       'connect',
                       'disconnect',
                       'config_download',
                       'key_generated',
                       'revoked',
                       'expired'
                   ) NOT NULL,
    event_time     TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    bytes_sent     BIGINT       DEFAULT 0,
    bytes_received BIGINT       DEFAULT 0,
    notes          VARCHAR(255) DEFAULT NULL,
    KEY idx_logs_user_id    (user_id),
    KEY idx_logs_event_time (event_time),
    KEY idx_logs_event_type (event_type),
    CONSTRAINT fk_logs_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -----------------------------------------------------------
-- IP Address Pool  (10.8.0.2 – 10.8.0.254)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS ip_pool (
    id           INT        AUTO_INCREMENT PRIMARY KEY,
    ip_address   VARCHAR(20) NOT NULL,
    is_allocated TINYINT(1)  DEFAULT 0,
    allocated_to INT         NULL,
    allocated_at TIMESTAMP   NULL,
    UNIQUE KEY uq_ip_pool_address (ip_address),
    KEY idx_ip_pool_is_allocated (is_allocated),
    CONSTRAINT fk_ip_pool_user FOREIGN KEY (allocated_to)
        REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -----------------------------------------------------------
-- Populate IP pool via stored procedure
-- -----------------------------------------------------------
DROP PROCEDURE IF EXISTS fill_ip_pool;

DELIMITER $$
CREATE PROCEDURE fill_ip_pool()
BEGIN
    DECLARE i INT DEFAULT 2;
    WHILE i <= 254 DO
        INSERT IGNORE INTO ip_pool (ip_address)
        VALUES (CONCAT('10.8.0.', i));
        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;

CALL fill_ip_pool();
DROP PROCEDURE IF EXISTS fill_ip_pool;

-- -----------------------------------------------------------
-- NOTE: Create the first admin account by running:
--       python create_admin.py
-- This script uses werkzeug to hash the password correctly.
-- -----------------------------------------------------------
