-- ---------------------------------------------------------------------------
-- st_dealership migration: v3 fix pass
--
-- Run once against an EXISTING database, then restart st_dealership.
-- Fresh installs get all of this from sql/install.sql and can skip it.
--
-- NOTE ON SYNTAX: `ADD COLUMN IF NOT EXISTS` is MariaDB. Most FiveM servers
-- run MariaDB, so it is used here for safe re-runs. If you are on real
-- MySQL 8, drop the `IF NOT EXISTS` from each ALTER and just run them once
-- (they will error harmlessly if the column is already there).
-- ---------------------------------------------------------------------------

-- 1. The registry table shipped twice in the old install.sql, and the copy
--    that actually got created was the one MISSING these columns - which is
--    why /newdealership failed on a fresh database. Adds whatever is absent.
ALTER TABLE `st_dealership_registry`
    ADD COLUMN IF NOT EXISTS `blip_sprite` INT NOT NULL DEFAULT 225 AFTER `job`,
    ADD COLUMN IF NOT EXISTS `blip_color`  INT NOT NULL DEFAULT 3 AFTER `blip_sprite`,
    ADD COLUMN IF NOT EXISTS `blip_scale`  FLOAT NOT NULL DEFAULT 0.8 AFTER `blip_color`,
    ADD COLUMN IF NOT EXISTS `pos_x` FLOAT NOT NULL DEFAULT 0 AFTER `blip_scale`,
    ADD COLUMN IF NOT EXISTS `pos_y` FLOAT NOT NULL DEFAULT 0 AFTER `pos_x`,
    ADD COLUMN IF NOT EXISTS `pos_z` FLOAT NOT NULL DEFAULT 0 AFTER `pos_y`,
    ADD COLUMN IF NOT EXISTS `heading` FLOAT NOT NULL DEFAULT 0 AFTER `pos_z`;

-- 2. Trade-in offers now carry the mileage/condition they were appraised
--    at, so accepting one no longer resets the vehicle to factory-new.
ALTER TABLE `st_dealership_tradein_offers`
    ADD COLUMN IF NOT EXISTS `mileage` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `model`,
    ADD COLUMN IF NOT EXISTS `condition_json` LONGTEXT DEFAULT NULL AFTER `mileage`;

-- 3. Auctions record who consigned the vehicle, so the winning bid gets
--    paid to a seller instead of vanishing.
ALTER TABLE `st_dealership_auctions`
    ADD COLUMN IF NOT EXISTS `seller_dealership` VARCHAR(50) DEFAULT NULL AFTER `current_bidder`;

-- 4. Monthly sales targets are scoped to a real month now, so the
--    monthlyTargetHit commission bonus stops being permanent.
ALTER TABLE `st_dealership_employees`
    ADD COLUMN IF NOT EXISTS `month_key` VARCHAR(7) DEFAULT NULL AFTER `month_units_sold`;

-- Existing rows have an unknown month; clearing the counter means the
-- bonus has to be re-earned this month rather than staying permanently on.
UPDATE `st_dealership_employees` SET `month_units_sold` = 0 WHERE `month_key` IS NULL;
