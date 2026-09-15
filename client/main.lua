local QBX = exports.qbx_core

ST = ST or {}

-- ---------------------------------------------------------------------------
-- VEHICLE SPAWNING
--
-- Lives in main.lua rather than its own file on purpose. These are called
-- from six other client files, and a separate file is one more thing that
-- has to be present and listed in fxmanifest for any of them to work - a
-- stale manifest meant every caller died on "attempt to call a nil value".
-- main.lua is loaded by definition if the resource is running at all.
--
-- Why they exist: a freshly created vehicle is, as far as the engine is
-- concerned, ambient traffic. The population system will clean it up the
-- moment it decides there are too many vehicles about - which is why an
-- unclaimed spawn appears for a second and vanishes.
-- SetEntityAsMissionEntity is what says "this one is scripted, leave it
-- alone". client/purchase.lua always did that and its cars stayed; the test
-- drive and factory delivery spawns didn't, and theirs didn't.
--
-- The network flags matter for the same reason on a OneSync server: an
-- entity that can't migrate dies with the client that made it.
-- ---------------------------------------------------------------------------

--- Spawns a vehicle and claims it properly. Returns the entity, or nil plus
--- a reason.
---
--- opts:
---   networked   - default true. false for purely local props (showroom
---                 display cars nobody else needs to see).
---   plate       - number plate text
---   fuel        - 0-100
---   frozen      - freeze in place on spawn
---   invincible  - for display pieces
function ST.SpawnVehicle(model, coords, heading, opts)
    opts = opts or {}

    local hash = type(model) == 'number' and model or joaat(model)

    -- A model this client doesn't have would otherwise hang the request
    -- below for its full timeout and then spawn nothing.
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return nil, ('"%s" is not a vehicle model on this client'):format(tostring(model))
    end

    if not lib.requestModel(hash, 15000) then
        return nil, ('timed out loading "%s"'):format(tostring(model))
    end

    local networked = opts.networked ~= false

    local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, heading or 0.0, networked, false)
    SetModelAsNoLongerNeeded(hash)

    if not veh or veh == 0 or not DoesEntityExist(veh) then
        return nil, 'the engine refused to create the vehicle'
    end

    -- THE important line. Without it the vehicle is ambient traffic and the
    -- population system will delete it, usually within a second or two.
    SetEntityAsMissionEntity(veh, true, true)

    -- Stops the game treating it as an abandoned car: no hotwiring prompt,
    -- and it won't be culled as a stolen vehicle left in the street.
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehicleNeedsToBeHotwired(veh, false)
    SetVehRadioStation(veh, 'OFF')
    SetVehicleDirtLevel(veh, 0.0)

    if networked then
        local netId = NetworkGetNetworkIdFromEntity(veh)
        -- Without migration the vehicle belongs to this client alone and
        -- disappears the moment they drive out of their own scope.
        SetNetworkIdCanMigrate(netId, true)
        SetNetworkIdExistsOnAllMachines(netId, true)
    end

    if opts.plate then SetVehicleNumberPlateText(veh, opts.plate) end
    if opts.fuel then SetVehicleFuelLevel(veh, opts.fuel + 0.0) end
    if opts.frozen then FreezeEntityPosition(veh, true) end
    if opts.invincible then
        SetEntityInvincible(veh, true)
        SetVehicleDoorsLocked(veh, 2)
    end

    return veh
end

--- Counterpart to the above. DeleteEntity is unreliable on anything the
--- engine still considers ambient, so the claim is reasserted first.
--- Safe to call with nil or an already-deleted entity.
function ST.DeleteVehicle(veh)
    if not veh or not DoesEntityExist(veh) then return end

    SetEntityAsMissionEntity(veh, true, true)
    DeleteEntity(veh)

    if DoesEntityExist(veh) then
        SetEntityAsNoLongerNeeded(veh)
    end
end

-- ---------------------------------------------------------------------------
-- Dealership state
-- ---------------------------------------------------------------------------

ST.CurrentDealership = nil
-- Declared here as well as in client/registry.lua: main.lua loads first,
-- and its startup thread writes into this table. It only worked before
-- because that thread happened to yield on a callback long enough for
-- registry.lua to load - which is timing, not a guarantee.
ST.RuntimeDealerships = ST.RuntimeDealerships or {}

local blips = {} -- dealershipName -> blip handle, so branding updates can move/restyle it live
local showroomZones = {} -- dealershipName -> ox_target zone id, so a deleted dealership can be torn down
local entryPointsBuilt = {} -- dealershipName -> true, so live-created dealerships aren't set up twice

local function createBlip(name, loc, branding)
    local blip = AddBlipForCoord(loc.x, loc.y, loc.z)
    SetBlipSprite(blip, branding.blipSprite)
    SetBlipColour(blip, branding.blipColor)
    SetBlipScale(blip, branding.blipScale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(branding.label)
    EndTextCommandSetBlipName(blip)
    blips[name] = blip
end

--- Applies a (possibly updated) branding table to an already-created blip,
--- called again whenever an owner saves new branding.
function ST.ApplyBranding(dealershipName, branding)
    local blip = blips[dealershipName]
    if not blip then return end
    SetBlipSprite(blip, branding.blipSprite)
    SetBlipColour(blip, branding.blipColor)
    SetBlipScale(blip, branding.blipScale)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(branding.label)
    EndTextCommandSetBlipName(blip)
end

--- The one interaction point every dealership always has, regardless of
--- whether the owner has configured any custom zones yet. Works for both
--- config/dealerships.lua entries and ones created with /newdealership.
--- Owners typically add a management_pc zone (client/zones.lua) too - for
--- /newdealership that one is created automatically at the spot the admin
--- placed, so the owner already has a working Dashboard target on day one.
function ST.SetupDealershipEntryPoint(name, dealership)
    if entryPointsBuilt[name] then return end
    entryPointsBuilt[name] = true

    local loc = dealership.location.showroom
    if not loc then return end

    local branding = lib.callback.await('st_dealership:server:getBranding', false, name)
        or { label = dealership.label, blipSprite = 225, blipColor = 3, blipScale = 0.8 }

    if dealership.location.blip then
        createBlip(name, dealership.location.blip, branding)
    end

    local zoneId = exports[Config.Target]:addBoxZone({
        coords = vector3(loc.x, loc.y, loc.z),
        size = vector3(2.0, 2.0, 3.0),
        rotation = 0,
        debug = Config.Debug,
        options = {
            {
                icon = 'fa-solid fa-car',
                label = 'Open Dealership',
                onSelect = function() ST.OpenDealershipUI(name) end,
            },
        },
    })
    showroomZones[name] = zoneId
end

--- Reverses ST.SetupDealershipEntryPoint - removes the blip and showroom
--- target for a dealership deleted via /admindealership. Zones (from
--- client/zones.lua) and lights (client/lighting.lua) tear themselves down
--- separately when their own sync tables stop including this dealership.
function ST.TeardownDealershipEntryPoint(name)
    if blips[name] then
        RemoveBlip(blips[name])
        blips[name] = nil
    end
    if showroomZones[name] then
        exports[Config.Target]:removeZone(showroomZones[name])
        showroomZones[name] = nil
    end
    entryPointsBuilt[name] = nil
    if ST.RuntimeDealerships then ST.RuntimeDealerships[name] = nil end
end

CreateThread(function()
    for name, dealership in pairs(Config.Dealerships) do
        ST.SetupDealershipEntryPoint(name, dealership)
    end

    -- Runtime-created dealerships (/newdealership) from a previous session,
    -- or created while this client was already connected but before this
    -- thread ran. Live creations after this point arrive via the
    -- 'dealershipCreated' event in client/registry.lua.
    local runtime = lib.callback.await('st_dealership:server:getAllDealerships', false) or {}
    for name, def in pairs(runtime) do
        if not Config.Dealerships[name] then
            ST.RuntimeDealerships[name] = def
            ST.SetupDealershipEntryPoint(name, def)
        end
    end
end)

function ST.GetPlayerJob()
    return QBX:GetPlayerData().job
end

function ST.GetLocalCitizenId()
    return QBX:GetPlayerData().citizenid
end
