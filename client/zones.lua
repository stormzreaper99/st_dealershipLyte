local QBX = exports.qbx_core
local zonesByDealership, activeTargetZones, activeLibZones = {}, {}, {}
local inPerimeterOf, permCache = nil, {}
local rebuildQueued = false
local promptVisible = false

local function permissionKey(dealership, permission)
    return dealership .. '|' .. permission
end

local function cachedPermission(dealership, permission)
    local key = permissionKey(dealership, permission)
    local cached = permCache[key]
    if cached ~= nil then return cached end

    -- Permission checks are only initiated when a target becomes interactable;
    -- once fetched, every target check is a local table lookup.
    CreateThread(function()
        local allowed = lib.callback.await('st_dealership:server:hasPermission', false, dealership, permission)
        permCache[key] = allowed == true
    end)
    return false
end

local function clearPermissionCache()
    permCache = {}
end
RegisterNetEvent('QBCore:Client:OnJobUpdate', clearPermissionCache)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', clearPermissionCache)
RegisterNetEvent('qbx_core:client:onJobUpdate', clearPermissionCache)

function ST.GetZonesOfType(dealership, zoneType)
    local result = {}
    for _, zone in ipairs(zonesByDealership[dealership] or {}) do
        if zone.zone_type == zoneType then result[#result + 1] = zone end
    end
    return result
end

local function hidePromptIfShown()
    if promptVisible then
        lib.hideTextUI()
        promptVisible = false
    end
end

local function teardownDynamicZones()
    for _, id in ipairs(activeTargetZones) do exports[Config.Target]:removeZone(id) end
    activeTargetZones = {}
    for _, handle in ipairs(activeLibZones) do handle:remove() end
    activeLibZones = {}
    hidePromptIfShown()
end

local function parsePoints(pointsJson)
    if not pointsJson then return nil end
    local ok, points = pcall(json.decode, pointsJson)
    if not ok or type(points) ~= 'table' or #points < 3 then return nil end
    local result = {}
    for _, point in ipairs(points) do result[#result + 1] = vector3(point.x, point.y, point.z) end
    return result
end

local function buildInteractableZone(zone, icon, defaultLabel, onInteract, canInteract)
    local label = zone.label and zone.label ~= '' and zone.label or defaultLabel
    if zone.interaction == 'press_e' then
        local shown = false
        local handle = lib.zones.sphere({
            coords = vector3(zone.pos_x, zone.pos_y, zone.pos_z),
            radius = 1.5,
            onEnter = function()
                if not canInteract or canInteract() then
                    lib.showTextUI(('[E] %s'):format(label))
                    shown, promptVisible = true, true
                end
            end,
            onExit = function()
                if shown then lib.hideTextUI(); shown, promptVisible = false, false end
            end,
            inside = function()
                if shown and IsControlJustPressed(0, 38) then onInteract() end
            end,
        })
        activeLibZones[#activeLibZones + 1] = handle
        return
    end

    activeTargetZones[#activeTargetZones + 1] = exports[Config.Target]:addSphereZone({
        coords = vector3(zone.pos_x, zone.pos_y, zone.pos_z),
        radius = 0.8,
        debug = Config.Debug,
        options = {{ icon = icon, label = label, onSelect = onInteract, canInteract = canInteract }},
    })
end

local function buildManagementPcTarget(dealership, zone)
    buildInteractableZone(zone, 'fa-solid fa-desktop', 'Management',
        function() ST.OpenDealershipUI(dealership, 'management') end,
        function() return cachedPermission(dealership, 'manage_finances') end)
end

local function buildCustomerShowroomTarget(dealership, zone)
    buildInteractableZone(zone, 'fa-solid fa-car-side', 'View Inventory', function() ST.OpenDealershipUI(dealership) end)
end

local function buildTradeInAppraisalTarget(dealership, zone)
    buildInteractableZone(zone, 'fa-solid fa-right-left', 'Get Appraisal', function() ST.OpenDealershipUI(dealership, 'tradein') end)
end

local function buildCustomTarget(dealership, zone)
    buildInteractableZone(zone, 'fa-solid fa-location-dot', 'Interact',
        function() TriggerEvent('st_dealership:customZoneTriggered', dealership, zone.id, zone.label) end)
end

local function buildPerimeterZone(dealership, zone)
    local points = parsePoints(zone.points_json)
    if not points then return end
    activeLibZones[#activeLibZones + 1] = lib.zones.poly({
        points = points,
        thickness = zone.height or 6,
        onExit = function()
            if inPerimeterOf == dealership then
                inPerimeterOf = nil
                if ST.IsTestDriveActive and ST.IsTestDriveActive() then
                    lib.notify({ title = 'Test Drive', description = "You're leaving dealership property.", type = 'inform' })
                end
            end
        end,
        inside = function() inPerimeterOf = dealership end,
    })
end

local function buildOfficeZone(dealership, zone)
    local points = parsePoints(zone.points_json)
    if not points then return end
    activeLibZones[#activeLibZones + 1] = lib.zones.poly({
        points = points,
        thickness = zone.height or 3,
        onEnter = function()
            if not cachedPermission(dealership, 'sell') then
                lib.notify({ title = zone.label ~= '' and zone.label or 'Office', description = 'Staff only.', type = 'inform' })
            end
        end,
    })
end

local function rebuildZones()
    rebuildQueued = false
    teardownDynamicZones()
    for dealership, zones in pairs(zonesByDealership) do
        for _, zone in ipairs(zones) do
            if zone.zone_type == 'management_pc' then buildManagementPcTarget(dealership, zone)
            elseif zone.zone_type == 'customer_showroom' then buildCustomerShowroomTarget(dealership, zone)
            elseif zone.zone_type == 'tradein_appraisal' then buildTradeInAppraisalTarget(dealership, zone)
            elseif zone.zone_type == 'custom' then buildCustomTarget(dealership, zone)
            elseif zone.zone_type == 'perimeter' then buildPerimeterZone(dealership, zone)
            elseif zone.zone_type == 'office' then buildOfficeZone(dealership, zone) end
        end
    end
end

-- requestFullSync sends dealerships one at a time. Debouncing prevents N full
-- teardown/rebuild cycles during startup when there are N dealerships.
local function queueRebuild()
    if rebuildQueued then return end
    rebuildQueued = true
    CreateThread(function()
        Wait(0)
        rebuildZones()
    end)
end

RegisterNetEvent('st_dealership:client:syncZones', function(dealership, zones)
    zonesByDealership[dealership] = zones or {}
    queueRebuild()
end)

RegisterNetEvent('st_dealership:client:brandingUpdated', function(dealership, branding)
    if ST.CurrentDealership == dealership and branding and branding.theme then
        SendNUIMessage({ action = 'theme', theme = branding.theme })
    end
end)

RegisterNetEvent('st_dealership:client:dealershipDeleted', function(dealership)
    zonesByDealership[dealership] = nil
    queueRebuild()
end)

local INPUT_GUARD_MS, PLACEMENT_TIMEOUT_MS = 250, 120000
local function confirmPressed() return IsControlJustPressed(0, 18) or IsControlJustPressed(0, 201) end
local function cancelPressed() return IsControlJustPressed(0, 177) or IsControlJustPressed(0, 194) end

function ST.CaptureZonePoint(zoneType)
    lib.showTextUI('[Enter] capture this spot   [Backspace] cancel')
    local started = GetGameTimer()
    while true do
        Wait(0)
        local elapsed = GetGameTimer() - started
        if elapsed > PLACEMENT_TIMEOUT_MS then
            lib.notify({ title = 'Zone', description = 'Placement timed out.', type = 'error' })
            return nil
        end
        if elapsed > INPUT_GUARD_MS then
            if confirmPressed() then
                local ped = PlayerPedId(); local coords = GetEntityCoords(ped)
                return { pos = { x = coords.x, y = coords.y, z = coords.z }, heading = GetEntityHeading(ped) }
            end
            if cancelPressed() then return nil end
        end
    end
end

function ST.CapturePolygon(zoneType)
    lib.showTextUI('[E] add corner   [Enter] finish (3+ corners)   [Backspace] undo/cancel')
    local points, started = {}, GetGameTimer()
    while true do
        Wait(0)
        local coords = GetEntityCoords(PlayerPedId())
        if GetGameTimer() - started > PLACEMENT_TIMEOUT_MS then
            lib.notify({ title = 'Zone', description = 'Placement timed out.', type = 'error' })
            return nil
        end
        for i, point in ipairs(points) do
            DrawMarker(1, point.x, point.y, point.z + .1, 0,0,0,0,0,0,.25,.25,.25,80,200,255,220,false,true,2,false,nil,nil,false)
            local nextPoint = points[i + 1]
            if nextPoint then DrawLine(point.x,point.y,point.z+.1,nextPoint.x,nextPoint.y,nextPoint.z+.1,80,200,255,200) end
        end
        if #points > 0 then
            local last = points[#points]
            DrawLine(last.x,last.y,last.z+.1,coords.x,coords.y,coords.z+.1,80,200,255,100)
            if #points >= 3 then local first=points[1];DrawLine(coords.x,coords.y,coords.z+.1,first.x,first.y,first.z+.1,80,200,255,60) end
        end
        if GetGameTimer() - started > INPUT_GUARD_MS then
            if IsControlJustPressed(0, 38) then points[#points + 1] = { x=coords.x, y=coords.y, z=coords.z } end
            if confirmPressed() then
                if #points >= 3 then return { points = points, heading = GetEntityHeading(PlayerPedId()) } end
                lib.notify({ title='Zone', description='Place at least 3 corners first.', type='error' })
            end
            if cancelPressed() then
                if #points > 0 then points[#points] = nil else return nil end
            end
        end
    end
end
