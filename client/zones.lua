local QBX = exports.qbx_core

local zonesByDealership = {}
local activeTargetZones = {}   -- ox_target zone IDs (returned by add*Zone) created from DB zones, for teardown on resync
local activeLibZones = {}      -- lib.zones handles (perimeter/office/press_e points), for teardown on resync
local inPerimeterOf = nil      -- dealership name the player is currently inside the perimeter of

-- ---------------------------------------------------------------------------
-- Permission cache
--
-- ox_target polls canInteract continuously while you're near a zone, so a
-- lib.callback.await in there fires a server round trip every frame at
-- close range. Permissions are cached per dealership+perm instead and
-- refreshed on job change, which is the only thing that can alter them.
-- ---------------------------------------------------------------------------
local permCache = {} -- ("dealership|perm") -> boolean

local function cachedPermission(dealershipName, perm)
    local key = dealershipName .. '|' .. perm
    local cached = permCache[key]
    if cached ~= nil then return cached end

    -- Unknown yet: kick off one lookup and answer false for now. The next
    -- poll (a frame later) gets the real answer from the cache.
    permCache[key] = false
    CreateThread(function()
        permCache[key] = lib.callback.await('st_dealership:server:hasPermission', false, dealershipName, perm) and true or false
    end)
    return false
end

local function clearPermissionCache()
    permCache = {}
end

RegisterNetEvent('QBCore:Client:OnJobUpdate', clearPermissionCache)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', clearPermissionCache)
RegisterNetEvent('qbx_core:client:onJobUpdate', clearPermissionCache)

function ST.GetZonesOfType(dealershipName, zoneType)
    local out = {}
    for _, z in ipairs(zonesByDealership[dealershipName] or {}) do
        if z.zone_type == zoneType then out[#out + 1] = z end
    end
    return out
end

local promptVisible = false

local function hidePromptIfShown()
    if promptVisible then
        lib.hideTextUI()
        promptVisible = false
    end
end

local function teardownDynamicZones()
    for _, zoneId in ipairs(activeTargetZones) do
        exports[Config.Target]:removeZone(zoneId)
    end
    activeTargetZones = {}

    for _, handle in ipairs(activeLibZones) do
        handle:remove()
    end
    activeLibZones = {}

    -- A zone removed while the player was standing in it would otherwise
    -- leave its "[E] ..." prompt stuck on screen forever.
    hidePromptIfShown()
end

local function parsePoints(pointsJson)
    if not pointsJson then return nil end
    local ok, points = pcall(json.decode, pointsJson)
    if not ok or not points or #points < 3 then return nil end
    local out = {}
    for _, p in ipairs(points) do
        out[#out + 1] = vector3(p.x, p.y, p.z)
    end
    return out
end

--- Shared builder for the point-zone types that need an interaction
--- (Owner's PC, Customer Inventory Viewing, Trade-In Appraisal, Custom).
--- `z.interaction` picks between an ox_target prompt ('target', the
--- default) or a plain proximity "press E" prompt ('press_e') - both do
--- the same thing once triggered, just via a different input method.
local function buildInteractableZone(z, icon, defaultLabel, onInteract, canInteract)
    local label = (z.label and z.label ~= '') and z.label or defaultLabel

    if z.interaction == 'press_e' then
        local promptShown = false
        local handle = lib.zones.sphere({
            coords = vector3(z.pos_x, z.pos_y, z.pos_z),
            radius = 1.5,
            onEnter = function()
                if not canInteract or canInteract() then
                    lib.showTextUI(('[E] %s'):format(label))
                    promptShown = true
                    promptVisible = true
                end
            end,
            onExit = function()
                if promptShown then lib.hideTextUI(); promptShown = false; promptVisible = false end
            end,
            inside = function()
                if promptShown and IsControlJustPressed(0, 38) then -- E
                    onInteract()
                end
            end,
        })
        activeLibZones[#activeLibZones + 1] = handle
    else
        local zoneId = exports[Config.Target]:addSphereZone({
            coords = vector3(z.pos_x, z.pos_y, z.pos_z),
            radius = 0.8,
            debug = Config.Debug,
            options = {
                {
                    icon = icon,
                    label = label,
                    onSelect = onInteract,
                    canInteract = canInteract,
                },
            },
        })
        activeTargetZones[#activeTargetZones + 1] = zoneId
    end
end

local function buildManagementPcTarget(dealershipName, z)
    buildInteractableZone(z, 'fa-solid fa-desktop', "Owner's PC",
        function() ST.OpenDealershipUI(dealershipName, 'dashboard') end,
        function() return cachedPermission(dealershipName, 'manage_finances') end)
end

local function buildCustomerShowroomTarget(dealershipName, z)
    buildInteractableZone(z, 'fa-solid fa-car-side', 'View Inventory',
        function() ST.OpenDealershipUI(dealershipName) end)
end

local function buildTradeInAppraisalTarget(dealershipName, z)
    buildInteractableZone(z, 'fa-solid fa-right-left', 'Get Appraisal',
        function() ST.OpenDealershipUI(dealershipName, 'tradein') end)
end

local function buildCustomTarget(dealershipName, z)
    buildInteractableZone(z, 'fa-solid fa-location-dot', 'Interact',
        function()
            -- Other resources can hook this to build whatever the owner
            -- intended the custom zone for.
            TriggerEvent('st_dealership:customZoneTriggered', dealershipName, z.id, z.label)
        end)
end

-- No canInteract here deliberately - checking "is there an order waiting"
-- would need a server round trip, and canInteract can run every frame at
-- close range (the same class of bug fixed in buildOfficeZone above).
-- ST.StartFactoryDelivery itself handles the "nothing to deliver" case
-- with a plain notify instead.
local function buildOrderTruckSpawnTarget(dealershipName, z)
    buildInteractableZone(z, 'fa-solid fa-truck', 'Start Delivery Run',
        function() ST.StartFactoryDelivery(dealershipName, z) end)
end

-- canInteract here is a pure local variable check (no server call), so
-- it's safe to run every frame - only ever shows once this player has an
-- active delivery in progress.
local function buildOrderReceiveZone(dealershipName, z)
    buildInteractableZone(z, 'fa-solid fa-warehouse', 'Turn In Delivery',
        function() ST.CompleteFactoryDelivery(dealershipName) end,
        function() return ST.ActiveDeliveryOrderId ~= nil and ST.ActiveDeliveryDealership == dealershipName end)
end

local function buildPerimeterZone(dealershipName, z)
    local points = parsePoints(z.points_json)
    if not points then return end

    local handle = lib.zones.poly({
        points = points,
        thickness = z.height or 6.0,
        onExit = function()
            if inPerimeterOf == dealershipName then
                inPerimeterOf = nil
                if ST.IsTestDriveActive and ST.IsTestDriveActive() then
                    lib.notify({ title = 'Test Drive', description = "You're leaving dealership property.", type = 'inform' })
                end
            end
        end,
        inside = function()
            inPerimeterOf = dealershipName
        end,
    })
    activeLibZones[#activeLibZones + 1] = handle
end

local function buildOfficeZone(dealershipName, z)
    local points = parsePoints(z.points_json)
    if not points then return end

    local handle = lib.zones.poly({
        points = points,
        thickness = z.height or 3.0,
        onEnter = function()
            local isStaff = cachedPermission(dealershipName, 'sell')
            if not isStaff then
                lib.notify({ title = (z.label ~= '' and z.label) or 'Office', description = 'Staff only.', type = 'inform' })
            end
        end,
    })
    activeLibZones[#activeLibZones + 1] = handle
end

local function rebuildZones()
    teardownDynamicZones()
    for dealershipName, zones in pairs(zonesByDealership) do
        for _, z in ipairs(zones) do
            if z.zone_type == 'management_pc' then buildManagementPcTarget(dealershipName, z)
            elseif z.zone_type == 'customer_showroom' then buildCustomerShowroomTarget(dealershipName, z)
            elseif z.zone_type == 'tradein_appraisal' then buildTradeInAppraisalTarget(dealershipName, z)
            elseif z.zone_type == 'custom' then buildCustomTarget(dealershipName, z)
            elseif z.zone_type == 'order_truck_spawn' then buildOrderTruckSpawnTarget(dealershipName, z)
            elseif z.zone_type == 'order_receive_zone' then buildOrderReceiveZone(dealershipName, z)
            elseif z.zone_type == 'perimeter' then buildPerimeterZone(dealershipName, z)
            elseif z.zone_type == 'office' then buildOfficeZone(dealershipName, z)
            end
            -- vehicle_display / testdrive_spawn / purchase_spawn are read
            -- on demand (ST.GetZonesOfType) rather than built as targets.
        end
    end
end

RegisterNetEvent('st_dealership:client:syncZones', function(dealershipName, zones)
    zonesByDealership[dealershipName] = zones
    rebuildZones()
end)

RegisterNetEvent('st_dealership:client:brandingUpdated', function(dealershipName, branding)
    ST.ApplyBranding(dealershipName, branding)
end)

RegisterNetEvent('st_dealership:client:dealershipDeleted', function(dealershipName)
    zonesByDealership[dealershipName] = nil
    rebuildZones()
end)

-- ---------------------------------------------------------------------------
-- Placement input
--
-- Confirm accepts Enter (18) and numpad Enter (201); cancel accepts both
-- IDs in common use for Backspace (177 and 194) - the old code only
-- listened for 194, so on some setups Backspace simply did nothing and the
-- only way out of the loop was to confirm.
--
-- INPUT_GUARD_MS exists because the mouse click that opened the tool can
-- still read as "just pressed" on the first frames, which would confirm
-- the placement instantly at whatever the player happened to be standing.
--
-- These return their result to ST.RunPlacement (client/nui.lua), which owns
-- hiding/restoring the UI. They deliberately no longer touch SetNuiFocus or
-- SendNUIMessage themselves.
-- ---------------------------------------------------------------------------
local INPUT_GUARD_MS = 250
local PLACEMENT_TIMEOUT_MS = 120000

local function confirmPressed()
    return IsControlJustPressed(0, 18) or IsControlJustPressed(0, 201)
end

local function cancelPressed()
    return IsControlJustPressed(0, 177) or IsControlJustPressed(0, 194)
end

-- ---------------------------------------------------------------------------
-- Point zone placement - captures the player's current position/heading
-- directly (used for management_pc, customer_showroom, tradein_appraisal,
-- vehicle_display, testdrive_spawn, purchase_spawn, custom).
-- ---------------------------------------------------------------------------
function ST.CaptureZonePoint(zoneType)
    lib.showTextUI('[Enter] capture this spot   [Backspace] cancel')

    local startedAt = GetGameTimer()

    while true do
        Wait(0)

        local elapsed = GetGameTimer() - startedAt

        -- Never let the tool run forever: if the player wanders off or
        -- alt-tabs out mid-placement, it gives up and hands control back
        -- instead of holding the interface hostage.
        if elapsed > PLACEMENT_TIMEOUT_MS then
            lib.notify({ title = 'Zone', description = 'Placement timed out.', type = 'error' })
            return nil
        end

        if elapsed > INPUT_GUARD_MS then
            if confirmPressed() then
                local ped = PlayerPedId()
                local coords = GetEntityCoords(ped)
                return { pos = { x = coords.x, y = coords.y, z = coords.z }, heading = GetEntityHeading(ped) }
            end
            if cancelPressed() then
                return nil
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Polygon zone placement (perimeter/office) - walk the property line,
-- press E at each corner, Enter to finish once you have 3+, Backspace
-- undoes the last corner (or cancels entirely if none are placed yet).
-- ---------------------------------------------------------------------------
function ST.CapturePolygon(zoneType)
    lib.showTextUI('[E] add corner   [Enter] finish (3+ corners)   [Backspace] undo/cancel')

    local points = {}
    local startedAt = GetGameTimer()

    while true do
        Wait(0)
        local coords = GetEntityCoords(PlayerPedId())

        if (GetGameTimer() - startedAt) > PLACEMENT_TIMEOUT_MS then
            lib.notify({ title = 'Zone', description = 'Placement timed out.', type = 'error' })
            return nil
        end

        for i, p in ipairs(points) do
            DrawMarker(1, p.x, p.y, p.z + 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.25, 0.25, 0.25, 80, 200, 255, 220, false, true, 2, false, nil, nil, false)
            local nextP = points[i + 1]
            if nextP then
                DrawLine(p.x, p.y, p.z + 0.1, nextP.x, nextP.y, nextP.z + 0.1, 80, 200, 255, 200)
            end
        end
        if #points > 0 then
            local last = points[#points]
            DrawLine(last.x, last.y, last.z + 0.1, coords.x, coords.y, coords.z + 0.1, 80, 200, 255, 100)
            if #points >= 3 then
                local first = points[1]
                DrawLine(coords.x, coords.y, coords.z + 0.1, first.x, first.y, first.z + 0.1, 80, 200, 255, 60)
            end
        end

        if (GetGameTimer() - startedAt) > INPUT_GUARD_MS then
            if IsControlJustPressed(0, 38) then -- E: add a corner here
                points[#points + 1] = { x = coords.x, y = coords.y, z = coords.z }
            end

            if confirmPressed() then
                if #points >= 3 then
                    return { points = points, heading = GetEntityHeading(PlayerPedId()) }
                end
                lib.notify({ title = 'Zone', description = 'Place at least 3 corners first.', type = 'error' })
            end

            if cancelPressed() then
                if #points > 0 then
                    points[#points] = nil
                else
                    return nil
                end
            end
        end
    end
end
