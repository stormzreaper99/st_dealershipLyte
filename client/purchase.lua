local function pickSpawnPoint(dealershipName)
    local spots = ST.GetZonesOfType(dealershipName, 'purchase_spawn')
    if #spots > 0 then
        local z = spots[math.random(#spots)]
        return vector4(z.pos_x, z.pos_y, z.pos_z, z.heading)
    end

    local dealership = ST.ResolveDealership(dealershipName)
    local fallback = dealership and dealership.location.testDriveReturn
    if fallback then return vector4(fallback.x, fallback.y, fallback.z, fallback.w) end

    if dealership and dealership.location.spawns and #dealership.location.spawns > 0 then
        local s = dealership.location.spawns[1]
        return vector4(s.x, s.y, s.z, s.w)
    end

    return nil
end

--- Fallback path only - fires when qbx_vehicles isn't installed, or
--- Config.PurchaseGarage isn't set, or CreatePlayerVehicle failed
--- (see server/ownership.lua). Spawns a drivable copy but doesn't
--- register it with any garage/ownership resource - it just exists.
RegisterNetEvent('st_dealership:client:vehiclePurchased', function(dealershipName, model, vin)
    local spawn = pickSpawnPoint(dealershipName)
    if not spawn then
        -- The sale already completed server-side (money moved, contract
        -- created) by the time this fires - this only affects handing
        -- over the physical car, so the customer needs to know that part
        -- didn't happen rather than getting nothing with no explanation.
        lib.notify({
            title = 'New Vehicle',
            description = "Your purchase went through, but this dealership hasn't set up a pickup spot yet - contact staff to get your vehicle.",
            type = 'error',
        })
        return
    end

    local veh, spawnErr = ST.SpawnVehicle(model, spawn, spawn.w, {
        plate = vin:sub(-8),
        fuel = 100.0,
    })

    if not veh then
        lib.notify({ title = 'New Vehicle', description = ('Your vehicle is in your garage - it could not be delivered to the lot: %s'):format(tostring(spawnErr)), type = 'inform' })
        return
    end

    ST.GiveKeysForVehicle(veh)

    lib.notify({ title = 'New Vehicle', description = 'Your new vehicle is ready at the pickup point.', type = 'success' })
end)

--- The normal path when qbx_vehicles is installed and configured -
--- server/ownership.lua already registered ownership and spawned the
--- vehicle server-side (via qbx.spawnVehicle), so this just waits for it
--- to stream in on this client and hands over the keys.
RegisterNetEvent('st_dealership:client:ownedVehicleReady', function(netId, dealershipName)
    local attempts = 0
    local veh = NetworkGetEntityFromNetworkId(netId)
    while (not veh or veh == 0) and attempts < 50 do
        Wait(100)
        attempts = attempts + 1
        veh = NetworkGetEntityFromNetworkId(netId)
    end

    if not veh or veh == 0 then
        lib.notify({ title = 'New Vehicle', description = 'Your new vehicle is in your garage - it just failed to stream in for an immediate hand-off.', type = 'error' })
        return
    end

    ST.GiveKeysForVehicle(veh)
    lib.notify({ title = 'New Vehicle', description = "Your new vehicle is ready at the pickup point, and it's saved to your garage.", type = 'success' })
end)
