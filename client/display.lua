local displaysByDealership = {}  -- dealershipName -> [{zone_id, vin, model, asking_price, mileage}]
local spawnedVehicles = {}       -- zoneId -> { entity, model }
local DISPLAY_RENDER_DISTANCE = 60.0

RegisterNetEvent('st_dealership:client:syncDisplays', function(dealershipName, assignments)
    displaysByDealership[dealershipName] = assignments
end)

RegisterNetEvent('st_dealership:client:dealershipDeleted', function(dealershipName)
    displaysByDealership[dealershipName] = nil
end)

--- Every display vehicle is locked, frozen, and immune to damage - it's a
--- showroom prop, not a driveable/lootable car. Spawned unnetworked since
--- it's purely decorative and stationary, same reasoning as the lighting
--- system: every client just renders its own local copy.
local function spawnDisplay(zoneId, model, pos)
    -- Local rather than networked (every client renders its own), but it
    -- still has to be claimed as a mission entity - "local" doesn't exempt
    -- it from the population cleanup that was deleting showroom cars.
    local veh, spawnErr = ST.SpawnVehicle(model, pos, pos.w, {
        networked = false,
        plate = 'DISPLAY',
        frozen = true,
    })

    if not veh then
        print(('[st_dealership] display spawn failed for "%s": %s'):format(tostring(model), tostring(spawnErr)))
        return
    end

    SetEntityInvincible(veh, true)
    SetVehicleCanBeVisiblyDamaged(veh, false)
    SetVehicleDoorsLocked(veh, 2) -- locked, can't be entered
    SetVehicleDoorsLockedForAllPlayers(veh, true)
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleUndriveable(veh, true)
    SetEntityCollision(veh, true, true)

    spawnedVehicles[zoneId] = { entity = veh, model = model }
end

local function despawnDisplay(zoneId)
    local info = spawnedVehicles[zoneId]
    if info and DoesEntityExist(info.entity) then DeleteEntity(info.entity) end
    spawnedVehicles[zoneId] = nil
end

local function getWantedDisplays()
    local wanted = {} -- zoneId -> { model, pos = vector4 }
    for dealershipName, assignments in pairs(displaysByDealership) do
        local zoneById = {}
        for _, z in ipairs(ST.GetZonesOfType(dealershipName, 'vehicle_display')) do
            zoneById[z.id] = z
        end

        for _, a in ipairs(assignments) do
            local z = zoneById[a.zone_id]
            if z then
                wanted[a.zone_id] = { model = a.model, pos = vector4(z.pos_x, z.pos_y, z.pos_z, z.heading) }
            end
        end
    end
    return wanted
end

CreateThread(function()
    while true do
        Wait(2000)
        local coords = GetEntityCoords(PlayerPedId())
        local wanted = getWantedDisplays()

        -- despawn anything unassigned, out of range, or whose assigned
        -- model changed since it was spawned
        for zoneId, info in pairs(spawnedVehicles) do
            local w = wanted[zoneId]
            local dist = w and #(coords - vector3(w.pos.x, w.pos.y, w.pos.z)) or math.huge
            if not w or dist > DISPLAY_RENDER_DISTANCE or info.model ~= w.model then
                despawnDisplay(zoneId)
            end
        end

        -- spawn anything newly in range that isn't up already
        for zoneId, w in pairs(wanted) do
            if not spawnedVehicles[zoneId] then
                local dist = #(coords - vector3(w.pos.x, w.pos.y, w.pos.z))
                if dist <= DISPLAY_RENDER_DISTANCE then
                    spawnDisplay(zoneId, w.model, w.pos)
                end
            end
        end
    end
end)
