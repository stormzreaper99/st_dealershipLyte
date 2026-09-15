-- st_dealership v5 performance indexes
-- Run once on existing installations. Safe to run after the older migrations.

ALTER TABLE `st_dealership_vehicles`
    ADD INDEX `idx_dealer_status_updated` (`dealership`, `status`, `updated_at`),
    ADD INDEX `idx_vehicle_model` (`model`);

ALTER TABLE `st_dealership_contracts`
    ADD INDEX `idx_contract_dealership` (`dealership`),
    ADD INDEX `idx_contract_buyer` (`buyer_citizenid`);

ALTER TABLE `st_dealership_loans`
    ADD INDEX `idx_loan_status_due` (`status`, `next_due_at`),
    ADD INDEX `idx_loan_status_missed` (`status`, `missed_at`),
    ADD INDEX `idx_loan_contract` (`contract_id`);

ALTER TABLE `st_dealership_financing_requests`
    ADD INDEX `idx_finreq_dealer_status` (`dealership`, `status`),
    ADD INDEX `idx_finreq_citizen` (`citizenid`);

ALTER TABLE `st_dealership_auctions`
    ADD INDEX `idx_auction_status_end` (`status`, `ends_at`),
    ADD INDEX `idx_auction_seller` (`seller_dealership`);

ALTER TABLE `st_dealership_auction_bids`
    ADD INDEX `idx_bid_dealership` (`dealership`);

ALTER TABLE `st_dealership_employees`
    ADD INDEX `idx_employee_dealership_volume` (`dealership`, `sales_volume`);

ALTER TABLE `st_dealership_tradein_offers`
    ADD INDEX `idx_tradein_dealer_status` (`dealership`, `status`),
    ADD INDEX `idx_tradein_citizen_status` (`citizenid`, `status`);

ALTER TABLE `st_dealership_display_assignments`
    ADD INDEX `idx_display_vin` (`vin`);
