-- qbx_vehiclekeys is the only key script in the give/remove chain
-- (client/vehiclekeys.lua) whose API is server-side
-- (exports.qbx_vehiclekeys:GiveKeys/RemoveKeys take a real entity handle,
-- not a plate) - everything else in the chain is handled entirely
-- client-side. This just resolves the network id the client reports
-- into an entity server-side.
--
-- These are plain net events, so the netId is attacker-controlled: before,
-- any client could hand itself keys to ANY vehicle on the server just by
-- guessing network ids. Every request is now checked for proximity (you
-- have to actually be in or beside the car) and rate limited.

local MAX_KEY_DISTANCE = 8.0
local KEY_REQUEST_COOLDOWN_MS = 1000

local lastRequest = {}

local function resolveVehicleForPlayer(src, netId)
    netId = tonumber(netId)
    if not netId then return nil end

    local now = GetGameTimer()
    if lastRequest[src] and (now - lastRequest[src]) < KEY_REQUEST_COOLDOWN_MS then return nil end
    lastRequest[src] = now

    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    if GetEntityType(veh) ~= 2 then return nil end -- 2 = vehicle

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end

    if GetVehiclePedIsIn(ped) == veh then return veh end

    local pedCoords = GetEntityCoords(ped)
    local vehCoords = GetEntityCoords(veh)
    if #(pedCoords - vehCoords) > MAX_KEY_DISTANCE then return nil end

    return veh
end

RegisterNetEvent('st_dealership:server:giveVehicleKeys', function(netId)
    if GetResourceState('qbx_vehiclekeys') ~= 'started' then return end

    local src = source
    local veh = resolveVehicleForPlayer(src, netId)
    if not veh then return end

    exports.qbx_vehiclekeys:GiveKeys(src, veh, true)
end)

RegisterNetEvent('st_dealership:server:removeVehicleKeys', function(netId)
    if GetResourceState('qbx_vehiclekeys') ~= 'started' then return end

    local src = source
    local veh = resolveVehicleForPlayer(src, netId)
    if not veh then return end

    exports.qbx_vehiclekeys:RemoveKeys(src, veh, true)
end)

AddEventHandler('playerDropped', function()
    lastRequest[source] = nil
end)
