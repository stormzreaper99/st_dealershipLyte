--- Finds a purchase_spawn zone for this dealership (same fallback chain
--- client/purchase.lua used to do this client-side) - done server-side
--- now since qbx.spawnVehicle needs a spawn point up front, not somewhere
--- to warp an already-spawned entity to afterward.
local function pickPurchaseSpawn(dealershipName)
    local zones = ST.GetZones(dealershipName)
    local spots = {}
    for _, z in ipairs(zones) do
        if z.zone_type == 'purchase_spawn' then spots[#spots + 1] = z end
    end
    if #spots > 0 then
        local z = spots[math.random(#spots)]
        return vector4(z.pos_x, z.pos_y, z.pos_z, z.heading)
    end

    local dealership = ST.GetDealership(dealershipName)
    local fallback = dealership and dealership.location.testDriveReturn
    if fallback then return vector4(fallback.x, fallback.y, fallback.z, fallback.w) end

    if dealership and dealership.location.spawns and #dealership.location.spawns > 0 then
        local s = dealership.location.spawns[1]
        return vector4(s.x, s.y, s.z, s.w)
    end

    return nil
end

--- Called once a sale completes (server/sales.lua). Registers the vehicle
--- with qbx_vehicles so it persists in the buyer's garage, then spawns a
--- drivable copy right now for the same immediate hand-off UX the
--- dealership already had - just properly wired into ownership this time.
--- Falls back to the old client-only spawn (drivable now, but not saved
--- anywhere) if qbx_vehicles isn't installed or Config.PurchaseGarage
--- isn't set, so servers without it don't lose the feature entirely.
function ST.HandOverPurchasedVehicle(buyerCitizenId, dealershipName, model, vin)
    local QBX = exports.qbx_core
    local buyerPlayer = QBX:GetPlayerByCitizenId(buyerCitizenId)
    if not buyerPlayer then return end -- buyer offline right now; nothing to hand over

    local buyerSrc = buyerPlayer.PlayerData.source
    local plate = vin:sub(-8)

    if GetResourceState('qbx_vehicles') ~= 'started' then
        TriggerClientEvent('st_dealership:client:vehiclePurchased', buyerSrc, dealershipName, model, vin)
        return
    end

    if not Config.PurchaseGarage then
        print('[st_dealership] Config.PurchaseGarage is not set - vehicle purchases cannot be registered with qbx_vehicles without it. Falling back to a non-persistent spawn. Set Config.PurchaseGarage to one of your qbx_garages garage names to fix this.')
        TriggerClientEvent('st_dealership:client:vehiclePurchased', buyerSrc, dealershipName, model, vin)
        return
    end

    -- pcall'd: a version mismatch in qbx_vehicles' export signature would
    -- otherwise throw here, after the sale has already completed, and the
    -- buyer would get neither the car nor the fallback spawn.
    local callOk, vehicleId, err = pcall(function()
        return exports.qbx_vehicles:CreatePlayerVehicle({
            model = model,
            citizenid = buyerCitizenId,
            garage = Config.PurchaseGarage,
            props = { plate = plate, fuelLevel = 100.0 },
        })
    end)
    if not callOk then
        print(('[st_dealership] CreatePlayerVehicle errored for %s: %s'):format(vin, tostring(vehicleId)))
        TriggerClientEvent('st_dealership:client:vehiclePurchased', buyerSrc, dealershipName, model, vin)
        return
    end

    if not vehicleId then
        print(('[st_dealership] CreatePlayerVehicle failed for %s: %s'):format(vin, err and err.message or 'unknown error'))
        TriggerClientEvent('st_dealership:client:vehiclePurchased', buyerSrc, dealershipName, model, vin)
        return
    end

    local spawn = pickPurchaseSpawn(dealershipName)
    if not spawn then
        -- Ownership is registered either way - they just have to pull it
        -- from the garage themselves instead of driving off immediately.
        TriggerClientEvent('ox_lib:notify', buyerSrc, {
            title = 'New Vehicle',
            description = 'Your new vehicle is in your garage - this dealership has no pickup spot set up for an immediate hand-off.',
            type = 'success',
        })
        return
    end

    local spawnOk, netId, entity = pcall(function()
        return qbx.spawnVehicle({
            model = model,
            spawnSource = spawn,
            props = { plate = plate, fuelLevel = 100.0 },
        })
    end)

    if not spawnOk or not netId then
        TriggerClientEvent('ox_lib:notify', buyerSrc, {
            title = 'New Vehicle',
            description = 'Your new vehicle is in your garage - it could not be delivered to the lot right now.',
            type = 'inform',
        })
        return
    end

    if entity and entity ~= 0 then
        Entity(entity).state:set('vehicleid', vehicleId, true)
    end

    TriggerClientEvent('st_dealership:client:ownedVehicleReady', buyerSrc, netId, dealershipName)
end
