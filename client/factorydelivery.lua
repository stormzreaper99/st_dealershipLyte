ST.ActiveDeliveryOrderId = nil
ST.ActiveDeliveryDealership = nil

local activeTruck, activeTrailer
local activeCargo = {} -- entities attached to the trailer - not auto-deleted with it, must be cleaned up explicitly

local function deleteDeliveryEntities()
    for _, cargo in ipairs(activeCargo) do
        ST.DeleteVehicle(cargo)
    end
    activeCargo = {}

    ST.DeleteVehicle(activeTruck)
    ST.DeleteVehicle(activeTrailer)
    activeTruck, activeTrailer = nil, nil
end

-- ---------------------------------------------------------------------------
-- Spawning the rig
--
-- The truck and trailer used to be created at exactly the same coordinates
-- and then attached. Two articulated vehicles occupying one space is a
-- collision the engine resolves by removing one of them - which is why the
-- rig appeared for a moment and vanished. The trailer is now placed behind
-- the truck, along its heading, and they're only attached once both have
-- settled on the ground.
-- ---------------------------------------------------------------------------

local TRAILER_OFFSET = 12.0   -- metres behind the truck

--- Forward vector for a heading, in GTA's convention (0 = north, +Y).
local function forwardVector(heading)
    local rad = math.rad(heading)
    return -math.sin(rad), math.cos(rad)
end

--- Spawns truck + trailer as a coupled rig and puts the player in the cab.
--- Returns truck, trailer, or nil plus a reason.
local function spawnRig(coords, heading)
    -- Whatever is parked on the spawn point has to go, or the rig lands
    -- inside it and one of the two gets removed.
    ClearAreaOfVehicles(coords.x, coords.y, coords.z, 15.0, false, false, false, false, false)

    local fx, fy = forwardVector(heading)
    local trailerPoint = {
        x = coords.x - fx * TRAILER_OFFSET,
        y = coords.y - fy * TRAILER_OFFSET,
        z = coords.z,
    }

    local trailer, trailerErr = ST.SpawnVehicle(Config.FactoryDelivery.trailerModel, trailerPoint, heading)
    if not trailer then return nil, nil, trailerErr end

    local truck, truckErr = ST.SpawnVehicle(Config.FactoryDelivery.truckModel, coords, heading, { fuel = 100.0 })
    if not truck then
        ST.DeleteVehicle(trailer)
        return nil, nil, truckErr
    end

    -- Let both settle before coupling. Attaching on the same frame they
    -- were created gives the trailer no chance to find the ground, and it
    -- ends up hitched at an angle or half through the road.
    SetVehicleOnGroundProperly(truck)
    SetVehicleOnGroundProperly(trailer)
    Wait(100)

    if not DoesEntityExist(truck) or not DoesEntityExist(trailer) then
        ST.DeleteVehicle(truck)
        ST.DeleteVehicle(trailer)
        return nil, nil, 'the rig was removed immediately after spawning'
    end

    AttachVehicleToTrailer(truck, trailer, 10.0)

    return truck, trailer
end

--- Puts the player in the driver's seat rather than dropping a truck on
--- top of them, which is what spawning at their feet amounted to.
local function putPlayerInCab(truck)
    local ped = PlayerPedId()

    if IsPedInAnyVehicle(ped, false) then
        TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 16)
        Wait(250)
    end

    SetPedIntoVehicle(ped, truck, -1)
    SetVehicleEngineOn(truck, true, true, false)
end

--- Called from the order_truck_spawn zone's target option (client/zones.lua).
--- Claims the oldest awaiting order for this dealership and starts the run:
--- spawns the truck+trailer rig at this zone, puts the player in the cab,
--- gives keys, and sets a waypoint to Config.FactoryDelivery.pickupLocation.
function ST.StartFactoryDelivery(dealershipName, spawnZone)
    if ST.ActiveDeliveryOrderId then
        lib.notify({ title = 'Factory Delivery', description = 'You already have an active delivery run.', type = 'error' })
        return
    end

    local orders = lib.callback.await('st_dealership:server:getPendingOrders', false, dealershipName) or {}
    local target = nil
    for _, o in ipairs(orders) do
        if o.status == 'awaiting_pickup' then target = o; break end
    end
    if not target then
        lib.notify({ title = 'Factory Delivery', description = 'No orders waiting for pickup.', type = 'error' })
        return
    end

    local ok = lib.callback.await('st_dealership:server:startDeliveryRun', false, dealershipName, target.id)
    if not ok then
        lib.notify({ title = 'Factory Delivery', description = 'Someone else already claimed that order.', type = 'error' })
        return
    end

    ST.ActiveDeliveryOrderId = target.id
    ST.ActiveDeliveryDealership = dealershipName

    local spawnPoint = { x = spawnZone.pos_x, y = spawnZone.pos_y, z = spawnZone.pos_z }

    local truck, trailer, spawnErr = spawnRig(spawnPoint, spawnZone.heading + 0.0)

    if not truck then
        ST.ActiveDeliveryOrderId = nil
        ST.ActiveDeliveryDealership = nil
        lib.notify({ title = 'Factory Delivery', description = ('Could not spawn the truck: %s'):format(tostring(spawnErr)), type = 'error' })
        return
    end

    activeTruck, activeTrailer = truck, trailer

    ST.GiveKeysForVehicle(activeTruck)
    putPlayerInCab(activeTruck)
    SetNewWaypoint(Config.FactoryDelivery.pickupLocation.x, Config.FactoryDelivery.pickupLocation.y)

    lib.notify({ title = 'Factory Delivery', description = 'Truck is ready - follow the waypoint to pick up the order.', type = 'success' })
end

--- Called from the pickup ped's target option (registered below). Swaps
--- the empty truck+trailer for a freshly-spawned pair at the same spot,
--- this time with the two cargo cars already attached to the trailer -
--- simpler and more reliable than trying to attach cars onto a trailer
--- that's already been driven around, since the fresh pair's transform
--- is fully under our control from the moment it's created.
function ST.ReceiveFactoryOrder()
    if not ST.ActiveDeliveryOrderId then return end
    if not activeTruck or not DoesEntityExist(activeTruck) then
        lib.notify({ title = 'Factory Delivery', description = 'Bring the truck here first.', type = 'error' })
        return
    end

    local coords = GetEntityCoords(activeTruck)
    local heading = GetEntityHeading(activeTruck)

    deleteDeliveryEntities() -- the empty pair - no cargo attached yet, so this is just the truck+trailer

    local truck, trailer, spawnErr = spawnRig(coords, heading)

    if not truck then
        activeTruck, activeTrailer = nil, nil
        lib.notify({ title = 'Factory Delivery', description = ('Could not load the order: %s'):format(tostring(spawnErr)), type = 'error' })
        return
    end

    activeTruck, activeTrailer = truck, trailer
    AttachVehicleToTrailer(activeTruck, activeTrailer, 10.0)

    for i, model in ipairs(Config.FactoryDelivery.cargoCars) do
        local slot = Config.FactoryDelivery.trailerSlots[i]
        if slot then
            local hash = GetHashKey(model)
            -- Cargo is claimed too: it rides on the trailer for the whole
            -- delivery, and an unclaimed one used to blink out mid-route.
            local cargo = ST.SpawnVehicle(hash, { x = coords.x, y = coords.y, z = coords.z + 2.0 }, heading, {
                networked = false,
                invincible = true,
            })
            SetEntityInvincible(cargo, true)
            SetVehicleDoorsLocked(cargo, 2)
            FreezeEntityPosition(cargo, true)
            AttachEntityToEntity(cargo, activeTrailer, 0, slot.x, slot.y, slot.z, 0.0, 0.0, slot.heading or 0.0, false, false, false, false, 2, true)
            activeCargo[#activeCargo + 1] = cargo
        end
    end

    ST.GiveKeysForVehicle(activeTruck)
    lib.notify({ title = 'Factory Delivery', description = 'Order loaded up - head back to the dealership.', type = 'success' })
end

--- Called from the order_receive_zone's target/press-e option
--- (client/zones.lua). Finalizes the order server-side (creates the real
--- vehicle) and cleans up the truck/trailer/cargo regardless of whether
--- that succeeds, since a failure here shouldn't leave a truck stuck in
--- the player's inventory of active deliveries forever.
function ST.CompleteFactoryDelivery(dealershipName)
    if not ST.ActiveDeliveryOrderId or ST.ActiveDeliveryDealership ~= dealershipName then return end

    local orderId = ST.ActiveDeliveryOrderId
    local ok, result = lib.callback.await('st_dealership:server:completeFactoryDelivery', false, dealershipName, orderId)

    deleteDeliveryEntities()
    ST.ActiveDeliveryOrderId = nil
    ST.ActiveDeliveryDealership = nil

    if ok then
        lib.notify({ title = 'Factory Delivery', description = 'Delivery complete - added to inventory.', type = 'success' })
    else
        lib.notify({ title = 'Factory Delivery', description = 'Something went wrong finalizing that delivery: ' .. tostring(result), type = 'error' })
    end
end

-- ---------------------------------------------------------------------------
-- The pickup ped - one persistent, local-only ped per client at the
-- configured pickup location. "Receive Order" only shows once this player
-- has an active delivery, avoiding any server round-trip inside
-- canInteract (a pure local variable check is safe to run every frame).
-- ---------------------------------------------------------------------------
CreateThread(function()
    local loc = Config.FactoryDelivery.pickupLocation
    local hash = GetHashKey('s_m_y_construct_01')
    lib.requestModel(hash)

    local ped = CreatePed(0, hash, loc.x, loc.y, loc.z - 1.0, loc.w, false, false)
    SetModelAsNoLongerNeeded(hash)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    exports[Config.Target]:addLocalEntity(ped, {
        {
            icon = 'fa-solid fa-box',
            label = 'Receive Order',
            canInteract = function() return ST.ActiveDeliveryOrderId ~= nil end,
            onSelect = function() ST.ReceiveFactoryOrder() end,
        },
    })
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        deleteDeliveryEntities()
    end
end)
