--- Reads the vehicle the local player is currently sitting in, for the
--- trade-in appraisal flow. Returns nil if they aren't in a vehicle.
--- Mileage is randomized here as a placeholder - swap this for your
--- garage/mechanic resource's odometer export if you track real mileage.
--
-- `model` is resolved by hashing every model name in Shared.VehicleCatalog
-- and checking which one matches this vehicle's actual model hash -
-- GetDisplayNameFromVehicleModel() was used here previously, but a
-- vehicle's display name isn't guaranteed to match the spawn-name string
-- used as the catalog key (this resource's own catalog includes renamed/
-- custom models like 'sultanrsr34' where that's definitely not true), so
-- that would silently misidentify most non-exact-vanilla vehicles. If no
-- catalog model's hash matches, `model` comes back nil - appraiseTradeIn
-- already handles that as 'unknown_model' server-side.
function ST.GetCurrentVehicleInfo()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return nil end

    local hash = GetEntityModel(veh)
    local matchedModel = nil
    for modelName in pairs(ST.CatalogCache) do
        if GetHashKey(modelName) == hash then
            matchedModel = modelName
            break
        end
    end

    return {
        model = matchedModel,
        plate = GetVehicleNumberPlateText(veh):gsub('^%s+', ''):gsub('%s+$', ''),
        mileage = math.random(5000, 120000),
        netId = NetworkGetNetworkIdFromEntity(veh),
    }
end
