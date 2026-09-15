local function plateOf(veh) return GetVehicleNumberPlateText(veh):gsub('^%s+',''):gsub('%s+$','') end

function ST.GiveKeysForVehicle(veh)
    if not DoesEntityExist(veh) then return end
    local plate = plateOf(veh)
    if GetResourceState('MrNewbVehicleKeys') == 'started' then
        TriggerServerEvent('st_dealership:server:giveMrNewbKeys', plate)
    elseif GetResourceState('qbx_vehiclekeys') == 'started' then
        TriggerServerEvent('st_dealership:server:giveVehicleKeys', NetworkGetNetworkIdFromEntity(veh))
    elseif GetResourceState('qb-vehiclekeys') == 'started' then
        TriggerEvent('vehiclekeys:client:SetOwner', plate)
    elseif GetResourceState('qs-vehiclekeys') == 'started' then
        exports['qs-vehiclekeys']:GiveKeys(plate, GetDisplayNameFromVehicleModel(GetEntityModel(veh)))
    elseif GetResourceState('wasabi_carlock') == 'started' then
        exports.wasabi_carlock:GiveKey(plate)
    elseif GetResourceState('cd_garage') == 'started' then
        TriggerEvent('cd_garage:AddKeys', plate)
    elseif GetResourceState('mk_vehiclekeys') == 'started' then
        exports['mk_vehiclekeys']:AddKey(veh)
    elseif GetResourceState('okokgarage') == 'started' then
        TriggerServerEvent('okokGarage:GiveKeys', plate)
    elseif GetResourceState('t1ger_keys') == 'started' then
        TriggerServerEvent('t1ger_keys:updateOwnedKeys', plate, true)
    else
        TriggerEvent('st_dealership:client:vehicleKeysNeeded', veh, plate)
    end
end

function ST.RemoveKeysForVehicle(veh)
    if not DoesEntityExist(veh) then return end
    local plate = plateOf(veh)
    if GetResourceState('MrNewbVehicleKeys') == 'started' then
        TriggerServerEvent('st_dealership:server:removeMrNewbKeys', plate)
    elseif GetResourceState('qbx_vehiclekeys') == 'started' then
        TriggerServerEvent('st_dealership:server:removeVehicleKeys', NetworkGetNetworkIdFromEntity(veh))
    elseif GetResourceState('wasabi_carlock') == 'started' then
        exports.wasabi_carlock:RemoveKey(plate)
    elseif GetResourceState('cd_garage') == 'started' then
        TriggerEvent('cd_garage:RemoveKeys', plate)
    elseif GetResourceState('okokgarage') == 'started' then
        TriggerServerEvent('okokGarage:RemoveKeys', plate)
    else
        TriggerEvent('st_dealership:client:vehicleKeysRemovalNeeded', veh, plate)
    end
end
