-- v4 dealership refactor
-- Run once on existing installations before restarting the resource.
-- This removes the database structures belonging exclusively to the systems
-- removed in v4: factory orders/delivery, dealer transfers, custom lighting,
-- dealership reputation, and vehicle aging.

DROP TABLE IF EXISTS `st_dealership_pending_orders`;
DROP TABLE IF EXISTS `st_dealership_transfers`;
DROP TABLE IF EXISTS `st_dealership_lights`;
DROP TABLE IF EXISTS `st_dealership_reputation`;

ALTER TABLE `st_dealership_vehicles`
    DROP COLUMN IF EXISTS `days_on_lot`;

UPDATE `st_dealership_vehicles`
SET `acquisition_source` = 'wholesale_in'
WHERE `acquisition_source` = 'factory_order';
