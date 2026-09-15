function ST.GetLights(dealershipName)
    return MySQL.query.await('SELECT * FROM st_dealership_lights WHERE dealership = ?', { dealershipName }) or {}
end

lib.callback.register('st_dealership:server:getLights', function(src, dealershipName)
    return ST.GetLights(dealershipName)
end)

--- `light` = { type, label, pos={x,y,z}, dir={x,y,z}, color={r,g,b}, brightness, range, radius, falloff, shadow }
lib.callback.register('st_dealership:server:createLight', function(src, dealershipName, light)
    if not ST.HasPermission(src, dealershipName, 'configure_dealership') then return false, 'no_permission' end
    if not Config.LightTypes[light.type] then return false, 'invalid_type' end

    local id = MySQL.insert.await([[
        INSERT INTO st_dealership_lights
            (dealership, type, label, pos_x, pos_y, pos_z, dir_x, dir_y, dir_z,
             color_r, color_g, color_b, brightness, `range`, radius, falloff, shadow)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        dealershipName, light.type, light.label, light.pos.x, light.pos.y, light.pos.z,
        light.dir.x, light.dir.y, light.dir.z,
        light.color.r, light.color.g, light.color.b,
        light.brightness, light.range, light.radius, light.falloff, light.shadow and 1 or 0,
    })

    TriggerClientEvent('st_dealership:client:syncLights', -1, dealershipName, ST.GetLights(dealershipName))
    return true, id
end)

lib.callback.register('st_dealership:server:updateLight', function(src, dealershipName, id, light)
    if not ST.HasPermission(src, dealershipName, 'configure_dealership') then return false, 'no_permission' end

    MySQL.update([[
        UPDATE st_dealership_lights SET
            label = ?, pos_x = ?, pos_y = ?, pos_z = ?, dir_x = ?, dir_y = ?, dir_z = ?,
            color_r = ?, color_g = ?, color_b = ?, brightness = ?, `range` = ?, radius = ?, falloff = ?, shadow = ?, enabled = ?
        WHERE id = ? AND dealership = ?
    ]], {
        light.label, light.pos.x, light.pos.y, light.pos.z, light.dir.x, light.dir.y, light.dir.z,
        light.color.r, light.color.g, light.color.b, light.brightness, light.range, light.radius,
        light.falloff, light.shadow and 1 or 0, light.enabled == nil and 1 or (light.enabled and 1 or 0),
        id, dealershipName,
    })

    TriggerClientEvent('st_dealership:client:syncLights', -1, dealershipName, ST.GetLights(dealershipName))
    return true
end)

lib.callback.register('st_dealership:server:deleteLight', function(src, dealershipName, id)
    if not ST.HasPermission(src, dealershipName, 'configure_dealership') then return false, 'no_permission' end

    MySQL.query.await('DELETE FROM st_dealership_lights WHERE id = ? AND dealership = ?', { id, dealershipName })
    TriggerClientEvent('st_dealership:client:syncLights', -1, dealershipName, ST.GetLights(dealershipName))
    return true
end)

--- Pushes every dealership's lights to a player when they join, so the
--- render thread has data immediately without a per-dealership request.
AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    if not player then return end
    for name in pairs(ST.GetAllDealerships()) do
        TriggerClientEvent('st_dealership:client:syncLights', player.PlayerData.source, name, ST.GetLights(name))
    end
end)
