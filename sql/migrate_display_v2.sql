-- Run this once against your database, then restart st_dealership.
-- New in this pass: assigning display vehicles to vehicle_display zones.

CREATE TABLE IF NOT EXISTS `st_dealership_display_assignments` (
    `zone_id`     INT UNSIGNED NOT NULL PRIMARY KEY,
    `dealership`  VARCHAR(50) NOT NULL,
    `vin`         VARCHAR(20) NOT NULL,
    `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX (`dealership`)
) ENGINE=InnoDB;
