-- Run this once against your existing database, then restart st_dealership.

CREATE TABLE IF NOT EXISTS `st_dealership_transfers` (
    `id`              INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `from_dealership` VARCHAR(50) NOT NULL,
    `to_dealership`   VARCHAR(50) NOT NULL,
    `vin`             VARCHAR(20) NOT NULL,
    `cash_adjustment` DECIMAL(12,2) NOT NULL DEFAULT 0,
    `status`          VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending | accepted | declined | cancelled
    `created_at`      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX (`to_dealership`, `status`),
    INDEX (`from_dealership`, `status`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `st_dealership_pending_orders` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `dealership`    VARCHAR(50) NOT NULL,
    `citizenid`     VARCHAR(50) DEFAULT NULL, -- who's currently running the delivery; NULL until claimed
    `model`         VARCHAR(60) NOT NULL,
    `purchase_cost` DECIMAL(12,2) NOT NULL,
    `status`        VARCHAR(20) NOT NULL DEFAULT 'awaiting_pickup', -- awaiting_pickup | picking_up | delivered
    `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX (`dealership`, `status`)
) ENGINE=InnoDB;
