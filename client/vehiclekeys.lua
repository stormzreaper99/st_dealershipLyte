-- ---------------------------------------------------------------------------
-- Vehicle key script compatibility layer
--
-- There's no single standard for "give a player keys" across the FiveM
-- ecosystem, so this tries known scripts in order and stops at the first
-- one it finds running. Confirmed against each script's own docs where
-- noted; a couple of the *remove* calls are inferred by naming symmetry
-- with their own give call (e.g. AddKeys -> RemoveKeys) rather than
-- independently confirmed, since not every script publishes that half.
-- If none of these match what you run, the generic events at the bottom
-- let you wire in your own with a one-line handler.
-- ---------------------------------------------------------------------------

local function plateOf(veh)
    return GetVehicleNumberPlateText(veh):gsub('^%s+', ''):gsub('%s+$', '')
end

function ST.GiveKeysForVehicle(veh)
    if not DoesEntityExist(veh) then return end
    local plate = plateOf(veh)

    if GetResourceState('qbx_vehiclekeys') == 'started' then
        -- server-side export needs a real entity handle, so hand it a netId
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
        -- No known key script detected - other resources can hook this to
        -- add their own integration without touching st_dealership at all.
        TriggerEvent('st_dealership:client:vehicleKeysNeeded', veh, plate)
    end
end

function ST.RemoveKeysForVehicle(veh)
    if not DoesEntityExist(veh) then return end
    local plate = plateOf(veh)

    if GetResourceState('qbx_vehiclekeys') == 'started' then
        TriggerServerEvent('st_dealership:server:removeVehicleKeys', NetworkGetNetworkIdFromEntity(veh))
    elseif GetResourceState('wasabi_carlock') == 'started' then
        exports.wasabi_carlock:RemoveKey(plate)
    elseif GetResourceState('cd_garage') == 'started' then
        TriggerEvent('cd_garage:RemoveKeys', plate) -- inferred from AddKeys, not independently confirmed
    elseif GetResourceState('okokgarage') == 'started' then
        TriggerServerEvent('okokGarage:RemoveKeys', plate) -- inferred from GiveKeys, not independently confirmed
    else
        -- qb-vehiclekeys, qs-vehiclekeys, mk_vehiclekeys, and t1ger_keys
        -- don't have a confirmed remove call to fall back on here - the
        -- vehicle still gets deleted either way, so this is a minor
        -- leftover key entry on an otherwise-gone car, not a broken test
        -- drive. Hook this event if your key script needs a specific call:
        TriggerEvent('st_dealership:client:vehicleKeysRemovalNeeded', veh, plate)
    end
end
