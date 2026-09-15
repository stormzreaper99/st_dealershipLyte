local function agingLabel(days)
    if days >= Config.Aging.problem then return 'problem'
    elseif days >= Config.Aging.slow then return 'slow_seller'
    elseif days >= Config.Aging.aging then return 'aging'
    elseif days >= Config.Aging.normal then return 'settling'
    else return 'normal' end
end

--- Increments days_on_lot for every in_stock vehicle and fires a warning
--- event once a vehicle crosses a threshold, so a management UI/phone
--- notification resource can pick it up.
local function tick()
    MySQL.update("UPDATE st_dealership_vehicles SET days_on_lot = days_on_lot + 1 WHERE status = 'in_stock'")

    local aged = MySQL.query.await(
        "SELECT vin, dealership, model, days_on_lot FROM st_dealership_vehicles WHERE status = 'in_stock' AND days_on_lot >= ?",
        { Config.Aging.aging }) or {}

    for _, row in ipairs(aged) do
        local label = agingLabel(row.days_on_lot)
        TriggerEvent('st_dealership:vehicleAgingWarning', {
            vin = row.vin, dealership = row.dealership, model = row.model,
            daysOnLot = row.days_on_lot, label = label,
        })
    end
end

lib.callback.register('st_dealership:server:getAgingReport', function(src, dealershipName)
    local rows = MySQL.query.await(
        "SELECT vin, model, asking_price, days_on_lot FROM st_dealership_vehicles WHERE dealership = ? AND status = 'in_stock' AND days_on_lot >= ? ORDER BY days_on_lot DESC",
        { dealershipName, Config.Aging.aging }) or {}

    for _, row in ipairs(rows) do
        row.label = agingLabel(row.days_on_lot)
    end
    return rows
end)

--- Convenience for a management "clearance sale" action: discounts every
--- vehicle over `daysThreshold` by `percent`.
lib.callback.register('st_dealership:server:clearanceSale', function(src, dealershipName, daysThreshold, percent)
    if not ST.HasPermission(src, dealershipName, 'set_pricing') then return false, 'no_permission' end

    -- Unclamped before: percent > 100 produced negative asking prices, and
    -- a non-numeric value errored out mid-query.
    percent = tonumber(percent)
    daysThreshold = math.floor(tonumber(daysThreshold) or Config.Aging.aging)
    if not percent then return false, 'invalid_percent' end

    percent = Utils.Clamp(percent, 1, 90)
    if daysThreshold < 0 then daysThreshold = 0 end

    -- Never discount below the floor the negotiation engine enforces.
    MySQL.update([[
        UPDATE st_dealership_vehicles
        SET asking_price = GREATEST(min_price, asking_price * (1 - ?))
        WHERE dealership = ? AND status = 'in_stock' AND days_on_lot >= ?
    ]], { percent / 100, dealershipName, daysThreshold })

    return true, { percent = percent, daysThreshold = daysThreshold }
end)

CreateThread(function()
    while true do
        Wait(Config.AgingIntervalMs)
        tick()
    end
end)
