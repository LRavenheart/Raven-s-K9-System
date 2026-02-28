-- ============================================================
--  Raven's K9 System  |  rk9_install.sql
--  Author: Raven
--
--  Run this manually if you prefer, or let the resource
--  auto-create the tables on first start.
-- ============================================================

CREATE TABLE IF NOT EXISTS `ravens_k9_certs` (
    `id`             INT          AUTO_INCREMENT PRIMARY KEY,
    `citizenid`      VARCHAR(50)  NOT NULL,
    `cert_type`      VARCHAR(50)  NOT NULL,
    `issued_at`      INT          NOT NULL  COMMENT 'Unix timestamp — issue date',
    `expires_at`     INT          NOT NULL  COMMENT 'Unix timestamp — expiry (issued + 1yr)',
    `evaluator_id`   VARCHAR(50)  NOT NULL  COMMENT 'CitizenID of issuing evaluator',
    `evaluator_name` VARCHAR(100) NOT NULL  COMMENT 'Full name of issuing evaluator',
    UNIQUE KEY `rk9_unique_cert` (`citizenid`, `cert_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Raven K9 System — handler certifications';

CREATE TABLE IF NOT EXISTS `ravens_k9_evaluators` (
    `id`          INT          AUTO_INCREMENT PRIMARY KEY,
    `citizenid`   VARCHAR(50)  NOT NULL UNIQUE,
    `name`        VARCHAR(100) NOT NULL,
    `added_by`    VARCHAR(50)  NOT NULL  COMMENT 'CitizenID of admin who granted evaluator role',
    `added_at`    INT          NOT NULL  COMMENT 'Unix timestamp'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  COMMENT='Raven K9 System — authorised evaluators';
