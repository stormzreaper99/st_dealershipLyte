-- st_dealership install script
-- Run once against your server database (oxmysql).

CREATE TABLE IF NOT EXISTS `st_dealership_accounts` (
    `dealership`   VARCHAR(50) NOT NULL PRIMARY KEY,
    `balance`      DECIMAL(14,2) NOT NULL DEFAULT 0,
    `updated_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Individual vehicle inventory. This is the heart of the resource: every
-- row is one physical car, not a static config entry.
CREATE TABLE IF NOT EXISTS `st_dealership_vehicles` (
    `id`                INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `vin`               VARCHAR(20) NOT NULL UNIQUE,
    `dealership`        VARCHAR(50) NOT NULL,
    `model`             VARCHAR(60) NOT NULL,
    `plate`             VARCHAR(15) DEFAULT NULL,
    `mileage`           INT UNSIGNED NOT NULL DEFAULT 0,
    `condition_json`    LONGTEXT NOT NULL,           -- {engine=90, brakes=70, ...}
    `purchase_cost`     DECIMAL(12,2) NOT NULL DEFAULT 0,
    `asking_price`      DECIMAL(12,2) NOT NULL DEFAULT 0,
    `min_price`         DECIMAL(12,2) NOT NULL DEFAULT 0,
    `acquisition_source`VARCHAR(30) NOT NULL DEFAULT 'unknown', -- factory_order | auction | trade_in | repo | wholesale_in
    `previous_owners`   INT UNSIGNED NOT NULL DEFAULT 0,
    `accident_history`  LONGTEXT DEFAULT NULL,        -- JSON array of accident records
    `service_history`   LONGTEXT DEFAULT NULL,        -- JSON array of service records
    `modifications_json`LONGTEXT DEFAULT NULL,        -- JSON of mods applied
    `title_status`      VARCHAR(20) NOT NULL DEFAULT 'clean',
    `days_on_lot`       INT UNSIGNED NOT NULL DEFAULT 0,
    `financing_eligible`TINYINT(1) NOT NULL DEFAULT 1,
    `photos_json`       LONGTEXT DEFAULT NULL,        -- JSON array of photo urls/ids
    `status`            VARCHAR(20) NOT NULL DEFAULT 'in_stock', -- in_stock | reserved | sold | in_service | wholesaled | repossessed | on_order
    `inspected`         TINYINT(1) NOT NULL DEFAULT 0,
    `created_at`        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX (`dealership`, `status`),
    INDEX (`model`)
) ENGINE=InnoDB;

-- Full lifecycle history per VIN - persists even after the row above is
-- deleted/archived (e.g. after export to a player-owned garage resource).
CREATE TABLE IF NOT EXISTS `st_dealership_vehicle_history` (
    `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `vin`        VARCHAR(20) NOT NULL,
    `event`      VARCHAR(40) NOT NULL,   -- manufactured, sold, accident, repaired, traded_in, repossessed, listed, inspected
    `details`    LONGTEXT DEFAULT NULL,  -- JSON blob describing the event
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX (`vin`)
) ENGINE=InnoDB;

-- Sales contracts generated on every completed sale.
CREATE TABLE IF NOT EXISTS `st_dealership_contracts` (
    `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `vin`            VARCHAR(20) NOT NULL,
    `dealership`     VARCHAR(50) NOT NULL,
    `buyer_citizenid`VARCHAR(50) NOT NULL,
    `salesperson_citizenid` VARCHAR(50) DEFAULT NULL,
    `sale_price`     DECIMAL(12,2) NOT NULL,
    `trade_in_vin`   VARCHAR(20) DEFAULT NULL,
    `down_payment`   DECIMAL(12,2) NOT NULL DEFAULT 0,
    `financed`       TINYINT(1) NOT NULL DEFAULT 0,
    `apr`            DECIMAL(6,4) DEFAULT NULL,
    `term_months`    INT UNSIGNED DEFAULT NULL,
    `warranty_json`  LONGTEXT DEFAULT NULL,
    `created_at`     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Active loans tied to a contract. Drives the repossession system.
CREATE TABLE IF NOT EXISTS `st_dealership_loans` (
    `id`              INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `contract_id`     INT UNSIGNED NOT NULL,
    `citizenid`       VARCHAR(50) NOT NULL,
    `vin`             VARCHAR(20) NOT NULL,
    `principal`       DECIMAL(12,2) NOT NULL,
    `apr`             DECIMAL(6,4) NOT NULL,
    `term_months`     INT UNSIGNED NOT NULL,
    `monthly_payment` DECIMAL(12,2) NOT NULL,
    `balance`         DECIMAL(12,2) NOT NULL,
    `missed_payments` INT UNSIGNED NOT NULL DEFAULT 0,
    `missed_at`       TIMESTAMP NULL DEFAULT NULL, -- set the moment a payment is first missed; cleared on any payment
    `next_due_at`     TIMESTAMP NOT NULL,
    `status`          VARCHAR(20) NOT NULL DEFAULT 'active', -- active | paid_off | defaulted | repossessed
    `created_at`      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX (`citizenid`),
    INDEX (`status`)
) ENGINE=InnoDB;

-- Player credit history (simple internal score; can be overridden by an
-- external banking resource via the GetPlayerCreditScore export).
CREATE TABLE IF NOT EXISTS `st_dealership_credit` (
    `citizenid`  VARCHAR(50) NOT NULL PRIMARY KEY,
    `score`      INT UNSIGNED NOT NULL DEFAULT 600,
    `flagged_for_financing` TINYINT(1) NOT NULL DEFAULT 0, -- set after any repossession; gates self-service financing
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Pending manual financing requests from flagged customers - the
-- self-service auto-approval path is skipped for them; a Finance
-- department employee has to approve or deny each request explicitly.
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

-- Dealer-only auction listings.
CREATE TABLE IF NOT EXISTS `st_dealership_auctions` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `vin`           VARCHAR(20) NOT NULL,
    `source_type`   VARCHAR(20) NOT NULL DEFAULT 'random', -- random | fleet | repossession | trade_in | damaged | rare
    `starting_bid`  DECIMAL(12,2) NOT NULL,
    `current_bid`   DECIMAL(12,2) NOT NULL,
    `current_bidder`VARCHAR(50) DEFAULT NULL,       -- dealership name of top bidder
    `seller_dealership` VARCHAR(50) DEFAULT NULL,   -- who gets paid when it closes; NULL for house stock
    `ends_at`       TIMESTAMP NOT NULL,
    `status`        VARCHAR(20) NOT NULL DEFAULT 'open', -- open | closed | cancelled
    `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `st_dealership_auction_bids` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `auction_id`  INT UNSIGNED NOT NULL,
    `dealership`  VARCHAR(50) NOT NULL,
    `amount`      DECIMAL(12,2) NOT NULL,
    `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX (`auction_id`)
) ENGINE=InnoDB;

-- Live per-model market data, recomputed on Config.MarketIntervalMs.
CREATE TABLE IF NOT EXISTS `st_dealership_market` (
    `model`            VARCHAR(60) NOT NULL PRIMARY KEY,
    `avg_price`        DECIMAL(12,2) NOT NULL,
    `multiplier`       DECIMAL(6,3) NOT NULL DEFAULT 1.000,
    `units_listed`     INT UNSIGNED NOT NULL DEFAULT 0,
    `units_sold_recent`INT UNSIGNED NOT NULL DEFAULT 0,
    `updated_at`       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Dealership-level reputation.
CREATE TABLE IF NOT EXISTS `st_dealership_reputation` (
    `dealership`       VARCHAR(50) NOT NULL PRIMARY KEY,
    `overall`          DECIMAL(5,2) NOT NULL DEFAULT 75.00,
    `customer_service`  DECIMAL(5,2) NOT NULL DEFAULT 75.00,
    `pricing`           DECIMAL(5,2) NOT NULL DEFAULT 75.00,
    `honesty`            DECIMAL(5,2) NOT NULL DEFAULT 75.00,
    `vehicle_quality`    DECIMAL(5,2) NOT NULL DEFAULT 75.00,
    `financing_rep`      DECIMAL(5,2) NOT NULL DEFAULT 75.00,
    `sales_experience`   DECIMAL(5,2) NOT NULL DEFAULT 75.00,
    `after_sales_support` DECIMAL(5,2) NOT NULL DEFAULT 75.00,
    `updated_at`        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Per-employee (salesperson) statistics + commission ledger.
CREATE TABLE IF NOT EXISTS `st_dealership_employees` (
    `citizenid`         VARCHAR(50) NOT NULL,
    `dealership`         VARCHAR(50) NOT NULL,
    `vehicles_sold`      INT UNSIGNED NOT NULL DEFAULT 0,
    `sales_volume`       DECIMAL(14,2) NOT NULL DEFAULT 0,
    `negotiations_won`   INT UNSIGNED NOT NULL DEFAULT 0,
    `negotiations_total` INT UNSIGNED NOT NULL DEFAULT 0,
    `trade_ins_handled`  INT UNSIGNED NOT NULL DEFAULT 0,
    `financing_deals`    INT UNSIGNED NOT NULL DEFAULT 0,
    `satisfaction_total` DECIMAL(10,2) NOT NULL DEFAULT 0,
    `satisfaction_count` INT UNSIGNED NOT NULL DEFAULT 0,
    `month_units_sold`   INT UNSIGNED NOT NULL DEFAULT 0,
    `month_key`          VARCHAR(7) DEFAULT NULL,     -- 'YYYY-MM'; scopes month_units_sold so the target bonus resets
    `updated_at`         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`, `dealership`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `st_dealership_settings` (
    `dealership`  VARCHAR(50) NOT NULL PRIMARY KEY,
    `settings_json` LONGTEXT NOT NULL, -- commission overrides, advertising budget, etc.
    `updated_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Trade-in appraisals awaiting a player decision.
CREATE TABLE IF NOT EXISTS `st_dealership_tradein_offers` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `dealership`    VARCHAR(50) NOT NULL,
    `citizenid`     VARCHAR(50) NOT NULL,
    `plate`         VARCHAR(15) NOT NULL,
    `model`         VARCHAR(60) NOT NULL,
    `mileage`       INT UNSIGNED NOT NULL DEFAULT 0,
    `condition_json` LONGTEXT DEFAULT NULL,
    `appraised_value` DECIMAL(12,2) NOT NULL,
    `offer_amount`    DECIMAL(12,2) NOT NULL,
    `status`          VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending | accepted | declined | expired
    `created_at`      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Owner-placed custom lighting. Drawn client-side every frame from this
-- table (FiveM has no persistent light entity - see client/lighting.lua).
CREATE TABLE IF NOT EXISTS `st_dealership_lights` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `dealership`  VARCHAR(50) NOT NULL,
    `type`        VARCHAR(20) NOT NULL DEFAULT 'point', -- point | spot | flood
    `label`       VARCHAR(60) DEFAULT NULL,
    `pos_x` FLOAT NOT NULL, `pos_y` FLOAT NOT NULL, `pos_z` FLOAT NOT NULL,
    `dir_x` FLOAT NOT NULL DEFAULT 0, `dir_y` FLOAT NOT NULL DEFAULT 0, `dir_z` FLOAT NOT NULL DEFAULT -1,
    `color_r` SMALLINT UNSIGNED NOT NULL DEFAULT 255,
    `color_g` SMALLINT UNSIGNED NOT NULL DEFAULT 255,
    `color_b` SMALLINT UNSIGNED NOT NULL DEFAULT 255,
    `brightness` FLOAT NOT NULL DEFAULT 5.0,
    `range`      FLOAT NOT NULL DEFAULT 10.0,
    `radius`     FLOAT NOT NULL DEFAULT 5.0,    -- spot cone radius at target distance
    `falloff`    FLOAT NOT NULL DEFAULT 100.0,
    `shadow`     TINYINT(1) NOT NULL DEFAULT 0,
    `enabled`    TINYINT(1) NOT NULL DEFAULT 1,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX (`dealership`)
) ENGINE=InnoDB;

-- Owner-defined zones/targets: property perimeter, office, the management
-- PC, vehicle display slots, test-drive/purchase spawns, and any custom
-- point the owner wants an interaction at.
CREATE TABLE IF NOT EXISTS `st_dealership_zones` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `dealership`  VARCHAR(50) NOT NULL,
    `zone_type`   VARCHAR(30) NOT NULL, -- perimeter | office | management_pc | customer_showroom | tradein_appraisal | vehicle_display | testdrive_spawn | purchase_spawn | custom
    `shape`       VARCHAR(10) NOT NULL DEFAULT 'point', -- point | poly
    `interaction` VARCHAR(10) NOT NULL DEFAULT 'target', -- target | press_e (point zones only)
    `label`       VARCHAR(60) DEFAULT NULL,
    `pos_x` FLOAT NOT NULL, `pos_y` FLOAT NOT NULL, `pos_z` FLOAT NOT NULL,
    `heading`     FLOAT NOT NULL DEFAULT 0,
    `length`      FLOAT DEFAULT NULL,
    `width`       FLOAT DEFAULT NULL,
    `height`      FLOAT DEFAULT NULL,
    `points_json` LONGTEXT DEFAULT NULL, -- poly shape: JSON array of {x,y,z} corners
    `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX (`dealership`, `zone_type`)
) ENGINE=InnoDB;

-- Dealerships created in-game with /newdealership. config/dealerships.lua
-- entries still work unchanged; this table is only for ones created at
-- runtime, so nothing here needs a resource restart to take effect.
CREATE TABLE IF NOT EXISTS `st_dealership_registry` (
    `name`             VARCHAR(50) NOT NULL PRIMARY KEY,
    `label`            VARCHAR(80) NOT NULL,
    `type`             VARCHAR(30) NOT NULL DEFAULT 'used',
    `job`              VARCHAR(50) NOT NULL,
    `blip_sprite`      INT NOT NULL DEFAULT 225,
    `blip_color`       INT NOT NULL DEFAULT 3,
    `blip_scale`       FLOAT NOT NULL DEFAULT 0.8,
    `pos_x` FLOAT NOT NULL, `pos_y` FLOAT NOT NULL, `pos_z` FLOAT NOT NULL,
    `heading`          FLOAT NOT NULL DEFAULT 0,
    `starting_balance` DECIMAL(14,2) NOT NULL DEFAULT 0,
    `created_by`       VARCHAR(50) DEFAULT NULL,
    `created_at`       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Assigns a specific in-stock vehicle (by VIN) to a vehicle_display zone,
-- so it actually spawns there. One assignment per zone (zone_id is the PK).
CREATE TABLE IF NOT EXISTS `st_dealership_display_assignments` (
    `zone_id`     INT UNSIGNED NOT NULL PRIMARY KEY,
    `dealership`  VARCHAR(50) NOT NULL,
    `vin`         VARCHAR(20) NOT NULL,
    `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX (`dealership`)
) ENGINE=InnoDB;

-- Admin-added vehicles for the "Order from Factory" catalog, on top of the
-- built-in list in shared/vehicles.lua. Only rows in this table can be
-- removed via /admindealership - the built-ins stay config-only, same
-- pattern as config/dealerships.lua vs the runtime dealership registry.
CREATE TABLE IF NOT EXISTS `st_dealership_catalog` (
    `model`      VARCHAR(60) NOT NULL PRIMARY KEY,
    `label`      VARCHAR(80) NOT NULL,
    `category`   VARCHAR(30) NOT NULL DEFAULT 'sedan',
    `msrp`       DECIMAL(12,2) NOT NULL,
    `rarity`     VARCHAR(20) NOT NULL DEFAULT 'common',
    `added_by`   VARCHAR(50) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Dealer-to-dealer transfer offers - consent-gated (the receiving
-- dealership must Accept), unlike ST.TransferInventory itself which is a
-- low-level unilateral move only meant to be called once consent exists.
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

-- Factory orders in transit - the truck/trailer delivery run, not the
-- vehicle record itself (that's only created in st_dealership_vehicles
-- once the delivery actually completes).
CREATE TABLE IF NOT EXISTS `st_dealership_pending_orders` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `dealership`    VARCHAR(50) NOT NULL,
    `citizenid`     VARCHAR(50) DEFAULT NULL,
    `model`         VARCHAR(60) NOT NULL,
    `purchase_cost` DECIMAL(12,2) NOT NULL,
    `status`        VARCHAR(20) NOT NULL DEFAULT 'awaiting_pickup', -- awaiting_pickup | picking_up | delivered
    `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX (`dealership`, `status`)
) ENGINE=InnoDB;
