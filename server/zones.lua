function ST.GetZones(dealershipName)
    return MySQL.query.await('SELECT * FROM st_dealership_zones WHERE dealership = ?', { dealershipName }) or {}
end

lib.callback.register('st_dealership:server:getZones', function(src, dealershipName)
    return ST.GetZones(dealershipName)
end)

--- `zone` = { zoneType, shape, label, interaction, pos={x,y,z}, heading, length, width, height, points={{x,y,z},...} }
--- For poly shapes (perimeter/office), `pos` is computed here as the
--- centroid of `points` so the column stays populated for anything that
--- just needs a rough location (map overview, distance checks, etc).
lib.callback.register('st_dealership:server:createZone', function(src, dealershipName, zone)
    if not ST.HasPermission(src, dealershipName, 'configure_dealership') then return false, 'no_permission' end
    local typeDef = Config.ZoneTypes[zone.zoneType]
    if not typeDef then return false, 'invalid_type' end

    local shape = zone.shape or typeDef.shape
    local pos = zone.pos
    local pointsJson = nil

    if shape == 'poly' then
        if not zone.points or #zone.points < 3 then return false, 'not_enough_points' end
        local sumX, sumY, sumZ = 0, 0, 0
        for _, p in ipairs(zone.points) do
            sumX = sumX + p.x; sumY = sumY + p.y; sumZ = sumZ + p.z
        end
        local n = #zone.points
        pos = { x = sumX / n, y = sumY / n, z = sumZ / n }
        pointsJson = json.encode(zone.points)
    end

    local id = MySQL.insert.await([[
        INSERT INTO st_dealership_zones
            (dealership, zone_type, shape, interaction, label, pos_x, pos_y, pos_z, heading, length, width, height, points_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        dealershipName, zone.zoneType, shape, zone.interaction or 'target', zone.label,
        pos.x, pos.y, pos.z, zone.heading or 0.0,
        zone.length, zone.width, zone.height, pointsJson,
    })

    TriggerClientEvent('st_dealership:client:syncZones', -1, dealershipName, ST.GetZones(dealershipName))
    return true, id
end)

lib.callback.register('st_dealership:server:deleteZone', function(src, dealershipName, id)
    if not ST.HasPermission(src, dealershipName, 'configure_dealership') then return false, 'no_permission' end

    MySQL.query.await('DELETE FROM st_dealership_zones WHERE id = ? AND dealership = ?', { id, dealershipName })
    TriggerClientEvent('st_dealership:client:syncZones', -1, dealershipName, ST.GetZones(dealershipName))
    return true
end)

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    if not player then return end
    for name in pairs(ST.GetAllDealerships()) do
        TriggerClientEvent('st_dealership:client:syncZones', player.PlayerData.source, name, ST.GetZones(name))
    end
end)
