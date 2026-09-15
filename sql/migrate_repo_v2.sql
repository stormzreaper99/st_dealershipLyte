-- Run this once against your existing database, then restart st_dealership.

ALTER TABLE `st_dealership_loans`
    ADD COLUMN IF NOT EXISTS `missed_at` TIMESTAMP NULL DEFAULT NULL AFTER `missed_payments`;

ALTER TABLE `st_dealership_credit`
    ADD COLUMN IF NOT EXISTS `flagged_for_financing` TINYINT(1) NOT NULL DEFAULT 0 AFTER `score`;

CREATE TABLE IF NOT EXISTS `st_dealership_financing_requests` (
    `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `dealership`   VARCHAR(50) NOT NULL,
    `vin`          VARCHAR(20) NOT NULL,
    `citizenid`    VARCHAR(50) NOT NULL,
    `sale_price`   DECIMAL(12,2) NOT NULL,
    `down_payment` DECIMAL(12,2) NOT NULL,
    `term_months`  INT UNSIGNED NOT NULL,
    `apr`          DECIMAL(6,4) NOT NULL,
    `status`       VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending | approved | denied
    `created_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX (`dealership`, `status`)
) ENGINE=InnoDB;
