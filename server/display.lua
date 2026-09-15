function ST.GetDisplayAssignments(dealershipName)
    return MySQL.query.await([[
        SELECT a.zone_id, a.vin, v.model, v.asking_price, v.mileage
        FROM st_dealership_display_assignments a
        JOIN st_dealership_vehicles v ON v.vin = a.vin
        WHERE a.dealership = ? AND v.status = 'in_stock'
    ]], { dealershipName }) or {}
end

lib.callback.register('st_dealership:server:getDisplayZones', function(src, dealershipName)
    if not ST.HasPermission(src, dealershipName, 'set_pricing') then return {} end

    local zones = MySQL.query.await(
        "SELECT id, label, pos_x, pos_y, pos_z FROM st_dealership_zones WHERE dealership = ? AND zone_type = 'vehicle_display'",
        { dealershipName }) or {}
    local assignments = ST.GetDisplayAssignments(dealershipName)

    local byZone = {}
    for _, a in ipairs(assignments) do byZone[a.zone_id] = a end

    for _, z in ipairs(zones) do
        z.assignment = byZone[z.id]
    end
    return zones
end)

lib.callback.register('st_dealership:server:assignDisplayVehicle', function(src, dealershipName, zoneId, vin)
    if not ST.HasPermission(src, dealershipName, 'set_pricing') then return false, 'no_permission' end

    local vehicle = ST.GetVehicleByVin(vin)
    if not vehicle or vehicle.dealership ~= dealershipName then return false, 'not_found' end
    if vehicle.status ~= 'in_stock' then return false, 'not_in_stock' end

    MySQL.insert([[
        INSERT INTO st_dealership_display_assignments (zone_id, dealership, vin) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE vin = VALUES(vin)
    ]], { zoneId, dealershipName, vin })

    TriggerClientEvent('st_dealership:client:syncDisplays', -1, dealershipName, ST.GetDisplayAssignments(dealershipName))
    return true
end)

lib.callback.register('st_dealership:server:clearDisplayVehicle', function(src, dealershipName, zoneId)
    if not ST.HasPermission(src, dealershipName, 'set_pricing') then return false, 'no_permission' end

    MySQL.query.await('DELETE FROM st_dealership_display_assignments WHERE zone_id = ? AND dealership = ?', { zoneId, dealershipName })
    TriggerClientEvent('st_dealership:client:syncDisplays', -1, dealershipName, ST.GetDisplayAssignments(dealershipName))
    return true
end)

--- Clears a display assignment the moment its vehicle sells, so a display
--- slot doesn't keep showing a car that's no longer for sale.
function ST.ClearDisplayAssignmentForVin(dealershipName, vin)
    local row = MySQL.single.await('SELECT zone_id FROM st_dealership_display_assignments WHERE vin = ? AND dealership = ?', { vin, dealershipName })
    if not row then return end

    MySQL.query.await('DELETE FROM st_dealership_display_assignments WHERE zone_id = ?', { row.zone_id })
    TriggerClientEvent('st_dealership:client:syncDisplays', -1, dealershipName, ST.GetDisplayAssignments(dealershipName))
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    if not player then return end
    for name in pairs(ST.GetAllDealerships()) do
        TriggerClientEvent('st_dealership:client:syncDisplays', player.PlayerData.source, name, ST.GetDisplayAssignments(name))
    end
end)
