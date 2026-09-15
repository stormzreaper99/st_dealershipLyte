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
    if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    if GetVehiclePedIsIn(ped) == veh then return veh end
    if #(GetEntityCoords(ped) - GetEntityCoords(veh)) > MAX_KEY_DISTANCE then return nil end
    return veh
end

RegisterNetEvent('st_dealership:server:giveVehicleKeys', function(netId)
    if GetResourceState('qbx_vehiclekeys') ~= 'started' then return end
    local src, veh = source, resolveVehicleForPlayer(source, netId)
    if veh then exports.qbx_vehiclekeys:GiveKeys(src, veh, true) end
end)

RegisterNetEvent('st_dealership:server:removeVehicleKeys', function(netId)
    if GetResourceState('qbx_vehiclekeys') ~= 'started' then return end
    local src, veh = source, resolveVehicleForPlayer(source, netId)
    if veh then exports.qbx_vehiclekeys:RemoveKeys(src, veh, true) end
end)

-- MrNewbVehicleKeys exposes plate-based GiveKeysByPlate/RemoveKeysByPlate.
-- The player source is not part of the documented call, so the export is
-- invoked on the player's client by the compatibility layer.
AddEventHandler('playerDropped', function() lastRequest[source] = nil end)
