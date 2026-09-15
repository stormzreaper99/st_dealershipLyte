-- Run this once against your existing database, then restart st_dealership.
-- Safe to run even if some/all of these columns already exist - each one
-- is guarded so it won't error out on a column that's already there.

ALTER TABLE `st_dealership_zones`
    ADD COLUMN IF NOT EXISTS `interaction` VARCHAR(10) NOT NULL DEFAULT 'target' AFTER `shape`;

ALTER TABLE `st_dealership_zones`
    ADD COLUMN IF NOT EXISTS `points_json` LONGTEXT DEFAULT NULL AFTER `height`;
