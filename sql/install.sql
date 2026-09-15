-- st_dealership install script
-- Run once against your server database (oxmysql).

CREATE TABLE IF NOT EXISTS `st_dealership_accounts` (`dealership` VARCHAR(50) NOT NULL PRIMARY KEY, `balance` DECIMAL(14,2) NOT NULL DEFAULT 0, `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `st_dealership_vehicles` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `vin` VARCHAR(20) NOT NULL UNIQUE,
    `dealership` VARCHAR(50) NOT NULL,
    `model` VARCHAR(60) NOT NULL,
    `plate` VARCHAR(15) DEFAULT NULL,
    `mileage` INT UNSIGNED NOT NULL DEFAULT 0,
    `condition_json` LONGTEXT NOT NULL,
    `purchase_cost` DECIMAL(12,2) NOT NULL DEFAULT 0,
    `asking_price` DECIMAL(12,2) NOT NULL DEFAULT 0,
    `min_price` DECIMAL(12,2) NOT NULL DEFAULT 0,
    `acquisition_source` VARCHAR(30) NOT NULL DEFAULT 'unknown',
    `previous_owners` INT UNSIGNED NOT NULL DEFAULT 0,
    `accident_history` LONGTEXT DEFAULT NULL,
    `service_history` LONGTEXT DEFAULT NULL,
    `modifications_json` LONGTEXT DEFAULT NULL,
    `title_status` VARCHAR(20) NOT NULL DEFAULT 'clean',
    `financing_eligible` TINYINT(1) NOT NULL DEFAULT 1,
    `photos_json` LONGTEXT DEFAULT NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'in_stock',
    `inspected` TINYINT(1) NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_dealer_status_updated` (`dealership`, `status`, `updated_at`), INDEX `idx_vehicle_model` (`model`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `st_dealership_vehicle_history` (`id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, `vin` VARCHAR(20) NOT NULL, `event` VARCHAR(40) NOT NULL, `details` LONGTEXT DEFAULT NULL, `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX `idx_history_vin` (`vin`)) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `st_dealership_contracts` (`id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, `vin` VARCHAR(20) NOT NULL, `dealership` VARCHAR(50) NOT NULL, `buyer_citizenid` VARCHAR(50) NOT NULL, `salesperson_citizenid` VARCHAR(50) DEFAULT NULL, `sale_price` DECIMAL(12,2) NOT NULL, `trade_in_vin` VARCHAR(20) DEFAULT NULL, `down_payment` DECIMAL(12,2) NOT NULL DEFAULT 0, `financed` TINYINT(1) NOT NULL DEFAULT 0, `apr` DECIMAL(6,4) DEFAULT NULL, `term_months` INT UNSIGNED DEFAULT NULL, `warranty_json` LONGTEXT DEFAULT NULL, `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX `idx_contract_dealership` (`dealership`), INDEX `idx_contract_buyer` (`buyer_citizenid`)) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `st_dealership_loans` (`id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, `contract_id` INT UNSIGNED NOT NULL, `citizenid` VARCHAR(50) NOT NULL, `vin` VARCHAR(20) NOT NULL, `principal` DECIMAL(12,2) NOT NULL, `apr` DECIMAL(6,4) NOT NULL, `term_months` INT UNSIGNED NOT NULL, `monthly_payment` DECIMAL(12,2) NOT NULL, `balance` DECIMAL(12,2) NOT NULL, `missed_payments` INT UNSIGNED NOT NULL DEFAULT 0, `missed_at` TIMESTAMP NULL DEFAULT NULL, `next_due_at` TIMESTAMP NOT NULL, `status` VARCHAR(20) NOT NULL DEFAULT 'active', `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX `idx_loan_citizen` (`citizenid`), INDEX `idx_loan_status_due` (`status`, `next_due_at`), INDEX `idx_loan_status_missed` (`status`, `missed_at`), INDEX `idx_loan_contract` (`contract_id`)) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `st_dealership_credit` (`citizenid` VARCHAR(50) NOT NULL PRIMARY KEY, `score` INT UNSIGNED NOT NULL DEFAULT 600, `flagged_for_financing` TINYINT(1) NOT NULL DEFAULT 0, `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `st_dealership_financing_requests` (`id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, `dealership` VARCHAR(50) NOT NULL, `vin` VARCHAR(20) NOT NULL, `citizenid` VARCHAR(50) NOT NULL, `sale_price` DECIMAL(12,2) NOT NULL, `down_payment` DECIMAL(12,2) NOT NULL, `term_months` INT UNSIGNED NOT NULL, `apr` DECIMAL(6,4) NOT NULL, `status` VARCHAR(20) NOT NULL DEFAULT 'pending', `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX `idx_finreq_dealer_status` (`dealership`, `status`), INDEX `idx_finreq_citizen` (`citizenid`)) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `st_dealership_auctions` (`id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, `vin` VARCHAR(20) NOT NULL, `source_type` VARCHAR(20) NOT NULL DEFAULT 'random', `starting_bid` DECIMAL(12,2) NOT NULL, `current_bid` DECIMAL(12,2) NOT NULL, `current_bidder` VARCHAR(50) DEFAULT NULL, `seller_dealership` VARCHAR(50) DEFAULT NULL, `ends_at` TIMESTAMP NOT NULL, `status` VARCHAR(20) NOT NULL DEFAULT 'open', `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX `idx_auction_status_end` (`status`, `ends_at`), INDEX `idx_auction_seller` (`seller_dealership`)) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS `st_dealership_auction_bids` (`id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, `auction_id` INT UNSIGNED NOT NULL, `dealership` VARCHAR(50) NOT NULL, `amount` DECIMAL(12,2) NOT NULL, `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX `idx_bid_auction` (`auction_id`), INDEX `idx_bid_dealership` (`dealership`)) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `st_dealership_market` (`model` VARCHAR(60) NOT NULL PRIMARY KEY, `avg_price` DECIMAL(12,2) NOT NULL, `multiplier` DECIMAL(6,3) NOT NULL DEFAULT 1.000, `units_listed` INT UNSIGNED NOT NULL DEFAULT 0, `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `st_dealership_employees` (`citizenid` VARCHAR(50) NOT NULL, `dealership` VARCHAR(50) NOT NULL, `vehicles_sold` INT UNSIGNED NOT NULL DEFAULT 0, `sales_volume` DECIMAL(14,2) NOT NULL DEFAULT 0, `negotiations_won` INT UNSIGNED NOT NULL DEFAULT 0, `negotiations_total` INT UNSIGNED NOT NULL DEFAULT 0, `trade_ins_handled` INT UNSIGNED NOT NULL DEFAULT 0, `financing_deals` INT UNSIGNED NOT NULL DEFAULT 0, `satisfaction_total` DECIMAL(10,2) NOT NULL DEFAULT 0, `satisfaction_count` INT UNSIGNED NOT NULL DEFAULT 0, `month_units_sold` INT UNSIGNED NOT NULL DEFAULT 0, `month_key` VARCHAR(7) DEFAULT NULL, `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (`citizenid`, `dealership`), INDEX `idx_employee_dealership_volume` (`dealership`, `sales_volume`)) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `st_dealership_settings` (`dealership` VARCHAR(50) NOT NULL PRIMARY KEY, `settings_json` LONGTEXT NOT NULL, `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `st_dealership_tradein_offers` (`id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, `dealership` VARCHAR(50) NOT NULL, `citizenid` VARCHAR(50) NOT NULL, `plate` VARCHAR(15) NOT NULL, `model` VARCHAR(60) NOT NULL, `mileage` INT UNSIGNED NOT NULL DEFAULT 0, `condition_json` LONGTEXT DEFAULT NULL, `appraised_value` DECIMAL(12,2) NOT NULL, `offer_amount` DECIMAL(12,2) NOT NULL, `status` VARCHAR(20) NOT NULL DEFAULT 'pending', `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX `idx_tradein_dealer_status` (`dealership`, `status`), INDEX `idx_tradein_citizen_status` (`citizenid`, `status`)) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `st_dealership_zones` (`id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, `dealership` VARCHAR(50) NOT NULL, `zone_type` VARCHAR(30) NOT NULL, `shape` VARCHAR(10) NOT NULL DEFAULT 'point', `interaction` VARCHAR(10) NOT NULL DEFAULT 'target', `label` VARCHAR(60) DEFAULT NULL, `pos_x` FLOAT NOT NULL, `pos_y` FLOAT NOT NULL, `pos_z` FLOAT NOT NULL, `heading` FLOAT NOT NULL DEFAULT 0, `length` FLOAT DEFAULT NULL, `width` FLOAT DEFAULT NULL, `height` FLOAT DEFAULT NULL, `points_json` LONGTEXT DEFAULT NULL, `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX `idx_zone_dealer_type` (`dealership`, `zone_type`)) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `st_dealership_registry` (`name` VARCHAR(50) NOT NULL PRIMARY KEY, `label` VARCHAR(80) NOT NULL, `type` VARCHAR(30) NOT NULL DEFAULT 'used', `job` VARCHAR(50) NOT NULL, `blip_sprite` INT NOT NULL DEFAULT 225, `blip_color` INT NOT NULL DEFAULT 3, `blip_scale` FLOAT NOT NULL DEFAULT 0.8, `pos_x` FLOAT NOT NULL, `pos_y` FLOAT NOT NULL, `pos_z` FLOAT NOT NULL, `heading` FLOAT NOT NULL DEFAULT 0, `starting_balance` DECIMAL(14,2) NOT NULL DEFAULT 0, `created_by` VARCHAR(50) DEFAULT NULL, `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `st_dealership_display_assignments` (`zone_id` INT UNSIGNED NOT NULL PRIMARY KEY, `dealership` VARCHAR(50) NOT NULL, `vin` VARCHAR(20) NOT NULL, `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX `idx_display_dealer` (`dealership`), INDEX `idx_display_vin` (`vin`)) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS `st_dealership_catalog` (`model` VARCHAR(60) NOT NULL PRIMARY KEY, `label` VARCHAR(80) NOT NULL, `category` VARCHAR(30) NOT NULL DEFAULT 'sedan', `msrp` DECIMAL(12,2) NOT NULL, `rarity` VARCHAR(20) NOT NULL DEFAULT 'common', `added_by` VARCHAR(50) DEFAULT NULL, `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB;
