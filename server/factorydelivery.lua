--- Places a factory order. Unlike other acquisition sources, this doesn't
--- create the vehicle immediately - it charges the dealership now (same
--- pricing formula ST.AcquireVehicle uses for a new/factory vehicle) and
--- queues a pending_orders row. The actual vehicle only gets created once
--- someone completes the delivery run (see completeFactoryDelivery below).
lib.callback.register('st_dealership:server:submitFactoryOrder', function(src, dealershipName, model)
    if not ST.HasPermission(src, dealershipName, 'purchase_inventory') then return false, 'no_permission' end

    local catalog = ST.GetCatalogEntry(model)
    if not catalog then return false, 'unknown_model' end

    -- Cap how many orders can be in flight at once, so the "allow negative"
    -- stance below can't be used to run a dealership arbitrarily deep into
    -- the red in one sitting.
    local inFlight = MySQL.scalar.await(
        "SELECT COUNT(*) FROM st_dealership_pending_orders WHERE dealership = ? AND status IN ('awaiting_pickup','picking_up')",
        { dealershipName }) or 0
    if inFlight >= (Config.MaxPendingFactoryOrders or 10) then
        return false, 'too_many_pending_orders'
    end

    local purchaseCost = Utils.Round(catalog.msrp * 0.85)
    -- same "allow negative, don't hard-block" stance as ST.AcquireVehicle
    ST.AdjustBalance(dealershipName, -purchaseCost, true, 'factory-order')

    MySQL.insert([[
        INSERT INTO st_dealership_pending_orders (dealership, model, purchase_cost)
        VALUES (?, ?, ?)
    ]], { dealershipName, model, purchaseCost })

    return true
end)

--- Orders still awaiting or currently mid-delivery, for the Ops NUI list
--- and for the truck-spawn zone to know what's available to start.
lib.callback.register('st_dealership:server:getPendingOrders', function(src, dealershipName)
    if not ST.HasPermission(src, dealershipName, 'purchase_inventory') then return {} end

    return MySQL.query.await([[
        SELECT * FROM st_dealership_pending_orders
        WHERE dealership = ? AND status IN ('awaiting_pickup', 'picking_up')
        ORDER BY created_at ASC
    ]], { dealershipName }) or {}
end)

--- Claims an order for the calling player and starts their delivery run -
--- called when interacting with an order_truck_spawn zone. Only succeeds
--- against an order that's still awaiting pickup (not already claimed by
--- someone else), so two staff can't both start the same run.
lib.callback.register('st_dealership:server:startDeliveryRun', function(src, dealershipName, orderId)
    if not ST.HasPermission(src, dealershipName, 'purchase_inventory') then return false, 'no_permission' end

    local citizenId = ST.GetPlayerCitizenId(src)
    if not citizenId then return false, 'no_player' end

    local order = MySQL.single.await("SELECT * FROM st_dealership_pending_orders WHERE id = ? AND dealership = ? AND status = 'awaiting_pickup'", { orderId, dealershipName })
    if not order then return false, 'not_available' end

    MySQL.update("UPDATE st_dealership_pending_orders SET status = 'picking_up', citizenid = ? WHERE id = ?", { citizenId, orderId })

    return true, { model = order.model }
end)

--- Turns in a completed delivery run at the order_receive_zone. Only the
--- player who claimed the run can complete it, and only while it's still
--- 'picking_up' - this is what actually creates the vehicle (payment
--- already happened at order time, so skipPayment avoids double-charging).
lib.callback.register('st_dealership:server:completeFactoryDelivery', function(src, dealershipName, orderId)
    if not ST.HasPermission(src, dealershipName, 'purchase_inventory') then return false, 'no_permission' end

    local citizenId = ST.GetPlayerCitizenId(src)
    local order = MySQL.single.await("SELECT * FROM st_dealership_pending_orders WHERE id = ? AND dealership = ? AND status = 'picking_up'", { orderId, dealershipName })
    if not order then return false, 'not_found' end
    if order.citizenid ~= citizenId then return false, 'not_your_run' end

    local ok, vehicleData = ST.AcquireVehicle(dealershipName, order.model, 'factory_order', {
        purchaseCost = tonumber(order.purchase_cost),
        skipPayment = true,
    })
    if not ok then return false, vehicleData end

    MySQL.update("UPDATE st_dealership_pending_orders SET status = 'delivered' WHERE id = ?", { orderId })

    return true, { vehicle = vehicleData }
end)
