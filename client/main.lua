local QBX = exports.qbx_core
ST = ST or {}

function ST.SpawnVehicle(model, coords, heading, opts)
    opts = opts or {}
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return nil, ('"%s" is not a vehicle model on this client'):format(tostring(model))
    end
    if not lib.requestModel(hash, 15000) then
        return nil, ('timed out loading "%s"'):format(tostring(model))
    end
    local networked = opts.networked ~= false
    local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, heading or 0.0, networked, false)
    SetModelAsNoLongerNeeded(hash)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil, 'the engine refused to create the vehicle' end

    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehicleNeedsToBeHotwired(veh, false)
    SetVehRadioStation(veh, 'OFF')
    SetVehicleDirtLevel(veh, 0.0)

    if networked then
        local netId = NetworkGetNetworkIdFromEntity(veh)
        SetNetworkIdCanMigrate(netId, true)
    end
    if opts.plate then SetVehicleNumberPlateText(veh, opts.plate) end
    if opts.fuel then SetVehicleFuelLevel(veh, opts.fuel + 0.0) end
    if opts.frozen then FreezeEntityPosition(veh, true) end
    if opts.invincible then SetEntityInvincible(veh, true); SetVehicleDoorsLocked(veh, 2) end
    return veh
end

function ST.DeleteVehicle(veh)
    if not veh or not DoesEntityExist(veh) then return end
    local deleted = false
    pcall(function() deleted = qbx.deleteVehicle(veh) == true end)
    if not deleted then
        SetEntityAsMissionEntity(veh, true, true)
        DeleteEntity(veh)
        if DoesEntityExist(veh) then SetEntityAsNoLongerNeeded(veh) end
    end
end

ST.CurrentDealership = nil
ST.RuntimeDealerships = ST.RuntimeDealerships or {}
local blips, showroomZones, entryPointsBuilt = {}, {}, {}

local function createBlip(name, loc, branding)
    local blip = AddBlipForCoord(loc.x, loc.y, loc.z)
    SetBlipSprite(blip, branding.blipSprite); SetBlipColour(blip, branding.blipColor); SetBlipScale(blip, branding.blipScale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString(branding.label); EndTextCommandSetBlipName(blip)
    blips[name] = blip
end

function ST.ApplyBranding(dealershipName, branding)
    local blip = blips[dealershipName]
    if not blip then return end
    SetBlipSprite(blip, branding.blipSprite); SetBlipColour(blip, branding.blipColor); SetBlipScale(blip, branding.blipScale)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString(branding.label); EndTextCommandSetBlipName(blip)
end

function ST.SetupDealershipEntryPoint(name, dealership)
    if entryPointsBuilt[name] then return end
    local loc = dealership.location and dealership.location.showroom
    if not loc then return end
    entryPointsBuilt[name] = true
    local branding = lib.callback.await('st_dealership:server:getBranding', false, name)
        or { label = dealership.label, blipSprite = 225, blipColor = 3, blipScale = 0.8 }
    if dealership.location.blip then createBlip(name, dealership.location.blip, branding) end
    showroomZones[name] = exports[Config.Target]:addBoxZone({
        coords = vector3(loc.x, loc.y, loc.z), size = vector3(2.0, 2.0, 3.0), rotation = 0, debug = Config.Debug,
        options = {{ icon = 'fa-solid fa-car', label = 'Open Dealership', onSelect = function() ST.OpenDealershipUI(name) end }},
    })
end

function ST.TeardownDealershipEntryPoint(name)
    if blips[name] then RemoveBlip(blips[name]); blips[name] = nil end
    if showroomZones[name] then exports[Config.Target]:removeZone(showroomZones[name]); showroomZones[name] = nil end
    entryPointsBuilt[name] = nil
    if ST.RuntimeDealerships then ST.RuntimeDealerships[name] = nil end
end

CreateThread(function()
    for name, dealership in pairs(Config.Dealerships) do ST.SetupDealershipEntryPoint(name, dealership) end
    local runtime = lib.callback.await('st_dealership:server:getAllDealerships', false) or {}
    for name, def in pairs(runtime) do
        if not Config.Dealerships[name] then ST.RuntimeDealerships[name] = def; ST.SetupDealershipEntryPoint(name, def) end
    end
end)

function ST.GetPlayerJob() return QBX.PlayerData.job end
function ST.GetLocalCitizenId() return QBX.PlayerData.citizenid end
