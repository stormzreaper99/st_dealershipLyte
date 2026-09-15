local QBX = exports.qbx_core

local zonesByDealership = {}
local activeTargetZones = {}
local activeLibZones = {}
local inPerimeterOf = nil
local permCache = {}

local function cachedPermission(dealershipName, perm)
    local key = dealershipName .. '|' .. perm
    local cached = permCache[key]
    if cached ~= nil then return cached end
    permCache[key] = false
    CreateThread(function() permCache[key] = lib.callback.await('st_dealership:server:hasPermission', false, dealershipName, perm) and true or false end)
    return false
end
local function clearPermissionCache() permCache = {} end
RegisterNetEvent('QBCore:Client:OnJobUpdate', clearPermissionCache)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', clearPermissionCache)
RegisterNetEvent('qbx_core:client:onJobUpdate', clearPermissionCache)

function ST.GetZonesOfType(dealershipName, zoneType)
    local out = {}
    for _, z in ipairs(zonesByDealership[dealershipName] or {}) do if z.zone_type == zoneType then out[#out+1] = z end end
    return out
end

local promptVisible = false
local function hidePromptIfShown() if promptVisible then lib.hideTextUI(); promptVisible = false end end
local function teardownDynamicZones()
    for _, zoneId in ipairs(activeTargetZones) do exports[Config.Target]:removeZone(zoneId) end
    activeTargetZones = {}
    for _, handle in ipairs(activeLibZones) do handle:remove() end
    activeLibZones = {}
    hidePromptIfShown()
end
local function parsePoints(pointsJson)
    if not pointsJson then return nil end
    local ok, points = pcall(json.decode, pointsJson)
    if not ok or not points or #points < 3 then return nil end
    local out = {}; for _, p in ipairs(points) do out[#out+1] = vector3(p.x,p.y,p.z) end
    return out
end

local function buildInteractableZone(z, icon, defaultLabel, onInteract, canInteract)
    local label = (z.label and z.label ~= '') and z.label or defaultLabel
    if z.interaction == 'press_e' then
        local promptShown = false
        local handle = lib.zones.sphere({
            coords=vector3(z.pos_x,z.pos_y,z.pos_z),radius=1.5,
            onEnter=function() if not canInteract or canInteract() then lib.showTextUI(('[E] %s'):format(label));promptShown=true;promptVisible=true end end,
            onExit=function() if promptShown then lib.hideTextUI();promptShown=false;promptVisible=false end end,
            inside=function() if promptShown and IsControlJustPressed(0,38) then onInteract() end end,
        })
        activeLibZones[#activeLibZones+1]=handle
    else
        local zoneId=exports[Config.Target]:addSphereZone({coords=vector3(z.pos_x,z.pos_y,z.pos_z),radius=.8,debug=Config.Debug,options={{icon=icon,label=label,onSelect=onInteract,canInteract=canInteract}}})
        activeTargetZones[#activeTargetZones+1]=zoneId
    end
end
local function buildManagementPcTarget(dealershipName,z) buildInteractableZone(z,'fa-solid fa-desktop','Management',function() ST.OpenDealershipUI(dealershipName,'management') end,function() return cachedPermission(dealershipName,'manage_finances') end) end
local function buildCustomerShowroomTarget(dealershipName,z) buildInteractableZone(z,'fa-solid fa-car-side','View Inventory',function() ST.OpenDealershipUI(dealershipName) end) end
local function buildTradeInAppraisalTarget(dealershipName,z) buildInteractableZone(z,'fa-solid fa-right-left','Get Appraisal',function() ST.OpenDealershipUI(dealershipName,'tradein') end) end
local function buildCustomTarget(dealershipName,z) buildInteractableZone(z,'fa-solid fa-location-dot','Interact',function() TriggerEvent('st_dealership:customZoneTriggered',dealershipName,z.id,z.label) end) end
local function buildPerimeterZone(dealershipName,z)
    local points=parsePoints(z.points_json);if not points then return end
    local handle=lib.zones.poly({points=points,thickness=z.height or 6.0,onExit=function() if inPerimeterOf==dealershipName then inPerimeterOf=nil;if ST.IsTestDriveActive and ST.IsTestDriveActive() then lib.notify({title='Test Drive',description="You're leaving dealership property.",type='inform'}) end end end,inside=function() inPerimeterOf=dealershipName end})
    activeLibZones[#activeLibZones+1]=handle
end
local function buildOfficeZone(dealershipName,z)
    local points=parsePoints(z.points_json);if not points then return end
    local handle=lib.zones.poly({points=points,thickness=z.height or 3.0,onEnter=function() if not cachedPermission(dealershipName,'sell') then lib.notify({title=(z.label~='' and z.label) or 'Office',description='Staff only.',type='inform'}) end end})
    activeLibZones[#activeLibZones+1]=handle
end
local function rebuildZones()
    teardownDynamicZones()
    for dealershipName,zones in pairs(zonesByDealership) do
        for _,z in ipairs(zones) do
            if z.zone_type=='management_pc' then buildManagementPcTarget(dealershipName,z)
            elseif z.zone_type=='customer_showroom' then buildCustomerShowroomTarget(dealershipName,z)
            elseif z.zone_type=='tradein_appraisal' then buildTradeInAppraisalTarget(dealershipName,z)
            elseif z.zone_type=='custom' then buildCustomTarget(dealershipName,z)
            elseif z.zone_type=='perimeter' then buildPerimeterZone(dealershipName,z)
            elseif z.zone_type=='office' then buildOfficeZone(dealershipName,z) end
        end
    end
end
RegisterNetEvent('st_dealership:client:syncZones',function(dealershipName,zones) zonesByDealership[dealershipName]=zones;rebuildZones() end)
RegisterNetEvent('st_dealership:client:brandingUpdated',function(dealershipName,branding) ST.ApplyBranding(dealershipName,branding) end)
RegisterNetEvent('st_dealership:client:dealershipDeleted',function(dealershipName) zonesByDealership[dealershipName]=nil;rebuildZones() end)

local INPUT_GUARD_MS=250
local PLACEMENT_TIMEOUT_MS=120000
local function confirmPressed() return IsControlJustPressed(0,18) or IsControlJustPressed(0,201) end
local function cancelPressed() return IsControlJustPressed(0,177) or IsControlJustPressed(0,194) end
function ST.CaptureZonePoint(zoneType)
    lib.showTextUI('[Enter] capture this spot   [Backspace] cancel');local startedAt=GetGameTimer()
    while true do
        Wait(0);local elapsed=GetGameTimer()-startedAt
        if elapsed>PLACEMENT_TIMEOUT_MS then lib.notify({title='Zone',description='Placement timed out.',type='error'});return nil end
        if elapsed>INPUT_GUARD_MS then
            if confirmPressed() then local ped=PlayerPedId();local coords=GetEntityCoords(ped);return {pos={x=coords.x,y=coords.y,z=coords.z},heading=GetEntityHeading(ped)} end
            if cancelPressed() then return nil end
        end
    end
end
function ST.CapturePolygon(zoneType)
    lib.showTextUI('[E] add corner   [Enter] finish (3+ corners)   [Backspace] undo/cancel');local points={};local startedAt=GetGameTimer()
    while true do
        Wait(0);local coords=GetEntityCoords(PlayerPedId())
        if GetGameTimer()-startedAt>PLACEMENT_TIMEOUT_MS then lib.notify({title='Zone',description='Placement timed out.',type='error'});return nil end
        for i,p in ipairs(points) do DrawMarker(1,p.x,p.y,p.z+.1,0,0,0,0,0,0,.25,.25,.25,80,200,255,220,false,true,2,false,nil,nil,false);local n=points[i+1];if n then DrawLine(p.x,p.y,p.z+.1,n.x,n.y,n.z+.1,80,200,255,200) end end
        if #points>0 then local last=points[#points];DrawLine(last.x,last.y,last.z+.1,coords.x,coords.y,coords.z+.1,80,200,255,100);if #points>=3 then local first=points[1];DrawLine(coords.x,coords.y,coords.z+.1,first.x,first.y,first.z+.1,80,200,255,60) end end
        if GetGameTimer()-startedAt>INPUT_GUARD_MS then
            if IsControlJustPressed(0,38) then points[#points+1]={x=coords.x,y=coords.y,z=coords.z} end
            if confirmPressed() then if #points>=3 then return {points=points,heading=GetEntityHeading(PlayerPedId())} end;lib.notify({title='Zone',description='Place at least 3 corners first.',type='error'}) end
            if cancelPressed() then if #points>0 then points[#points]=nil else return nil end end
        end
    end
end
