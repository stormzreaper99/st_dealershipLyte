local displaysByDealership = {}
local spawnedVehicles = {}
local DISPLAY_RENDER_DISTANCE = 60.0
local DISPLAY_CHECK_INTERVAL = 2000
local wantedCache = {}
local wantedDirty = true

local function rebuildWantedCache()
    wantedCache = {}
    for dealershipName, assignments in pairs(displaysByDealership) do
        local zoneById = {}
        for _, z in ipairs(ST.GetZonesOfType(dealershipName, 'vehicle_display')) do
            zoneById[z.id] = z
        end
        for _, a in ipairs(assignments or {}) do
            local z = zoneById[a.zone_id]
            if z then
                wantedCache[a.zone_id] = {
                    model = a.model,
                    pos = vector4(z.pos_x, z.pos_y, z.pos_z, z.heading),
                }
            end
        end
    end
    wantedDirty = false
end

local function despawnDisplay(zoneId)
    local info = spawnedVehicles[zoneId]
    if info and DoesEntityExist(info.entity) then
        ST.DeleteVehicle(info.entity)
    end
    spawnedVehicles[zoneId] = nil
end

RegisterNetEvent('st_dealership:client:syncDisplays', function(dealershipName, assignments)
    displaysByDealership[dealershipName] = assignments or {}
    wantedDirty = true
end)

RegisterNetEvent('st_dealership:client:dealershipDeleted', function(dealershipName)
    displaysByDealership[dealershipName] = nil
    wantedDirty = true
end)

RegisterNetEvent('st_dealership:client:displayUpdated', function(dealershipName, assignments)
    displaysByDealership[dealershipName] = assignments or {}
    wantedDirty = true
end)

local function spawnDisplay(zoneId, model, pos)
    local veh, spawnErr = ST.SpawnVehicle(model, pos, pos.w, {
        networked = false,
        plate = 'DISPLAY',
        frozen = true,
        invincible = true,
    })
    if not veh then
        print(('[st_dealership] display spawn failed for "%s": %s'):format(tostring(model), tostring(spawnErr)))
        return
    end
    SetVehicleCanBeVisiblyDamaged(veh, false)
    SetVehicleDoorsLockedForAllPlayers(veh, true)
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleUndriveable(veh, true)
    SetEntityCollision(veh, true, true)
    spawnedVehicles[zoneId] = { entity = veh, model = model }
end

CreateThread(function()
    while true do
        Wait(DISPLAY_CHECK_INTERVAL)
        if wantedDirty then rebuildWantedCache() end

        local playerCoords = GetEntityCoords(PlayerPedId())
        for zoneId, info in pairs(spawnedVehicles) do
            local wanted = wantedCache[zoneId]
            local dist = wanted and #(playerCoords - vector3(wanted.pos.x, wanted.pos.y, wanted.pos.z)) or math.huge
            if not wanted or dist > DISPLAY_RENDER_DISTANCE or info.model ~= wanted.model then
                despawnDisplay(zoneId)
            end
        end

        for zoneId, wanted in pairs(wantedCache) do
            if not spawnedVehicles[zoneId] then
                local dist = #(playerCoords - vector3(wanted.pos.x, wanted.pos.y, wanted.pos.z))
                if dist <= DISPLAY_RENDER_DISTANCE then
                    spawnDisplay(zoneId, wanted.model, wanted.pos)
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for zoneId in pairs(spawnedVehicles) do despawnDisplay(zoneId) end
end)
