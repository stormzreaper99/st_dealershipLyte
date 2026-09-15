-- Run this once against your existing database, then restart st_dealership.
-- Safe on a fresh install too (plain CREATE TABLE IF NOT EXISTS).

CREATE TABLE IF NOT EXISTS `st_dealership_catalog` (
    `model`      VARCHAR(60) NOT NULL PRIMARY KEY,
    `label`      VARCHAR(80) NOT NULL,
    `category`   VARCHAR(30) NOT NULL DEFAULT 'sedan',
    `msrp`       DECIMAL(12,2) NOT NULL,
    `rarity`     VARCHAR(20) NOT NULL DEFAULT 'common',
    `added_by`   VARCHAR(50) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;
