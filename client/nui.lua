local nuiOpen = false
local placementActive = false
local lastTradeInVehicle = nil

function ST.IsPlacementActive() return placementActive end

function ST.RunPlacement(label, fn)
    if placementActive then return end
    placementActive = true
    SendNUIMessage({ action = 'close' })
    SetNuiFocus(false, false)
    local ok, payload = pcall(fn)
    if not ok then
        print(('[st_dealership] placement tool "%s" errored: %s'):format(label, tostring(payload)))
        payload = nil
        lib.notify({ title = 'Placement', description = 'The placement tool failed.', type = 'error' })
    end
    pcall(lib.hideTextUI)
    placementActive = false
    if not nuiOpen then SetNuiFocus(false, false); return end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'placementResult', data = payload })
end

local function closeNUI()
    if not nuiOpen then return end
    nuiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function buildCatalog()
    local source = (ST.CatalogCache and next(ST.CatalogCache)) and ST.CatalogCache or Shared.VehicleCatalog
    local list = {}
    for model, entry in pairs(source) do list[#list + 1] = { model = model, label = entry.label, category = entry.category, msrp = entry.msrp, rarity = entry.rarity } end
    table.sort(list, function(a,b) return (a.label or a.model) < (b.label or b.model) end)
    return list
end

local function buildZoneTypes()
    local list = {}
    for key, def in pairs(Config.ZoneTypes) do list[#list + 1] = { key = key, label = def.label, shape = def.shape, icon = def.icon, interactable = def.interactable or false } end
    return list
end

function ST.OpenDealershipUI(dealershipName, initialView)
    local dealership = ST.ResolveDealership(dealershipName)
    if not dealership then return end
    ST.CurrentDealership = dealershipName
    local meta = lib.callback.await('st_dealership:server:getDealershipMeta', false, dealershipName)
    if not meta then lib.notify({ title = 'Dealership', description = 'This dealership no longer exists.', type = 'error' }); return end
    local perms = lib.callback.await('st_dealership:server:getPermissions', false, dealershipName) or {}
    local branding = lib.callback.await('st_dealership:server:getBranding', false, dealershipName) or {}
    nuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = {
        dealership = { name = dealershipName, label = meta.label, type = meta.type, balance = meta.balance },
        permissions = perms, citizenId = ST.GetLocalCitizenId(), currencySymbol = Config.CurrencySymbol,
        financingTerms = Config.Financing.terms, catalog = buildCatalog(), zoneTypes = buildZoneTypes(),
        staffGrades = Config.StaffGrades, branding = branding, theme = branding.theme or meta.theme or Config.UITheme,
        initialView = initialView,
    } })
end

CreateThread(function()
    while true do
        Wait(0)
        if nuiOpen and not placementActive then if IsControlJustPressed(0, 200) then closeNUI() end else Wait(250) end
    end
end)

RegisterNUICallback('close', function(_, cb) closeNUI(); cb('ok') end)
RegisterNUICallback('getInventory', function(_, cb) cb(lib.callback.await('st_dealership:server:getInventory', false, ST.CurrentDealership) or {}) end)
RegisterNUICallback('getVehicle', function(data, cb) cb(lib.callback.await('st_dealership:server:getVehicle', false, data.vin)) end)
RegisterNUICallback('inspectVehicle', function(data, cb) local ok,result=lib.callback.await('st_dealership:server:inspectVehicle',false,data.vin); cb({ok=ok,result=result}) end)
RegisterNUICallback('evaluateOffer', function(data, cb) cb(lib.callback.await('st_dealership:server:evaluateOffer',false,data.vin,tonumber(data.offer))) end)
RegisterNUICallback('quoteFinancing', function(data, cb) cb(lib.callback.await('st_dealership:server:quoteFinancing',false,ST.GetLocalCitizenId(),tonumber(data.price),tonumber(data.downPayment),tonumber(data.termMonths))) end)
RegisterNUICallback('kioskPurchase', function(data, cb) local ok,result=lib.callback.await('st_dealership:server:kioskPurchase',false,data.vin,tonumber(data.finalPrice),data.dealOptions); cb({ok=ok,result=result}) end)
RegisterNUICallback('employeeSell', function(data, cb) local ok,result=lib.callback.await('st_dealership:server:sellVehicle',false,data.vin,data.buyerCitizenId,tonumber(data.finalPrice),data.dealOptions); cb({ok=ok,result=result}) end)
RegisterNUICallback('adjustPrice', function(data, cb) local ok,result=lib.callback.await('st_dealership:server:adjustPrice',false,data.vin,tonumber(data.price)); cb({ok=ok,result=result}) end)
RegisterNUICallback('setVehiclePhoto', function(data, cb) local ok,result=lib.callback.await('st_dealership:server:setVehiclePhoto',false,ST.CurrentDealership,data.vin,data.url); cb({ok=ok,result=result}) end)
RegisterNUICallback('clearVehiclePhoto', function(data, cb) local ok,result=lib.callback.await('st_dealership:server:clearVehiclePhoto',false,ST.CurrentDealership,data.vin); cb({ok=ok,result=result}) end)
RegisterNUICallback('appraiseTradeIn', function(_,cb) local info=ST.GetCurrentVehicleInfo(); if not info then cb({error='not_in_vehicle'}); return end; lastTradeInVehicle=info.netId; cb(lib.callback.await('st_dealership:server:appraiseTradeIn',false,ST.CurrentDealership,info)) end)
RegisterNUICallback('acceptTradeIn', function(data,cb) local ok,result=lib.callback.await('st_dealership:server:acceptTradeIn',false,data.offerId); if ok and lastTradeInVehicle then local veh=NetworkGetEntityFromNetworkId(lastTradeInVehicle); if veh and veh~=0 and DoesEntityExist(veh) then DeleteEntity(veh) end; lastTradeInVehicle=nil end; cb({ok=ok,result=result}) end)
RegisterNUICallback('startTestDrive', function(data,cb) local vehicle=lib.callback.await('st_dealership:server:getVehicle',false,data.vin); if vehicle then closeNUI(); ST.StartTestDrive(ST.CurrentDealership,vehicle) end; cb('ok') end)
RegisterNUICallback('endTestDrive', function(_,cb) ST.EndTestDrive('manual'); cb('ok') end)
RegisterNUICallback('getActiveLoans', function(_,cb) cb(lib.callback.await('st_dealership:server:getActiveLoans',false,ST.CurrentDealership) or {}) end)
RegisterNUICallback('pingFinancedVehicle', function(data,cb) local ok,result=lib.callback.await('st_dealership:server:pingFinancedVehicle',false,ST.CurrentDealership,data.loanId); if ok and result and result.coords then SetNewWaypoint(result.coords.x,result.coords.y) end; cb({ok=ok,result=result}) end)
RegisterNUICallback('completeRepo', function(data,cb) local ok,result=lib.callback.await('st_dealership:server:completeRepo',false,ST.CurrentDealership,data.loanId); cb({ok=ok,result=result}) end)
RegisterNUICallback('submitFinancingRequest', function(data,cb) local ok,result=lib.callback.await('st_dealership:server:submitFinancingRequest',false,ST.CurrentDealership,data.vin,data.finalPrice,data.downPayment,data.termMonths); cb({ok=ok,result=result}) end)
RegisterNUICallback('getFinancingRequests', function(_,cb) cb(lib.callback.await('st_dealership:server:getFinancingRequests',false,ST.CurrentDealership) or {}) end)
RegisterNUICallback('approveFinancingRequest', function(data,cb) local ok,result=lib.callback.await('st_dealership:server:approveFinancingRequest',false,ST.CurrentDealership,data.requestId); cb({ok=ok,result=result}) end)
RegisterNUICallback('denyFinancingRequest', function(data,cb) local ok,result=lib.callback.await('st_dealership:server:denyFinancingRequest',false,ST.CurrentDealership,data.requestId); cb({ok=ok,result=result}) end)
RegisterNUICallback('getOpenAuctions', function(_,cb) cb(lib.callback.await('st_dealership:server:getOpenAuctions',false) or {}) end)
RegisterNUICallback('placeBid', function(data,cb) local ok,result=lib.callback.await('st_dealership:server:placeBid',false,tonumber(data.auctionId),ST.CurrentDealership,tonumber(data.amount)); cb({ok=ok,result=result}) end)
RegisterNUICallback('sendToAuction', function(data,cb) local ok,result=lib.callback.await('st_dealership:server:sendToAuction',false,ST.CurrentDealership,data.vin,data.startingBid,data.durationMinutes); cb({ok=ok,result=result}) end)
RegisterNUICallback('getLeaderboard', function(_,cb) cb(lib.callback.await('st_dealership:server:getLeaderboard',false,ST.CurrentDealership) or {}) end)
RegisterNUICallback('getOnlineStaff', function(_,cb) cb(lib.callback.await('st_dealership:server:getOnlineStaff',false,ST.CurrentDealership) or {}) end)
RegisterNUICallback('hireStaff', function(data,cb) local ok,result=lib.callback.await('st_dealership:server:hireStaff',false,ST.CurrentDealership,data.targetId,data.grade); cb({ok=ok,result=result}) end)
RegisterNUICallback('fireStaff', function(data,cb) local ok,result=lib.callback.await('st_dealership:server:fireStaff',false,ST.CurrentDealership,data.targetId); cb({ok=ok,result=result}) end)
RegisterNUICallback('getDisplayZones', function(_,cb) cb(lib.callback.await('st_dealership:server:getDisplayZones',false,ST.CurrentDealership) or {}) end)
RegisterNUICallback('assignDisplayVehicle', function(data,cb) local ok,result=lib.callback.await('st_dealership:server:assignDisplayVehicle',false,ST.CurrentDealership,data.zoneId,data.vin); cb({ok=ok,result=result}) end)
RegisterNUICallback('clearDisplayVehicle', function(data,cb) local ok,result=lib.callback.await('st_dealership:server:clearDisplayVehicle',false,ST.CurrentDealership,data.zoneId); cb({ok=ok,result=result}) end)
RegisterNUICallback('getBranding', function(_,cb) cb(lib.callback.await('st_dealership:server:getBranding',false,ST.CurrentDealership)) end)
RegisterNUICallback('updateBranding', function(data,cb) local ok,result=lib.callback.await('st_dealership:server:updateBranding',false,ST.CurrentDealership,data.branding); cb({ok=ok,result=result}) end)
RegisterNUICallback('getZones', function(_,cb) cb(lib.callback.await('st_dealership:server:getZones',false,ST.CurrentDealership) or {}) end)
RegisterNUICallback('startZoneCapture', function(data,cb) local zoneType=data.zoneType; CreateThread(function() ST.RunPlacement('zone-point',function() return {kind='zone',zoneType=zoneType,placement=ST.CaptureZonePoint(zoneType)} end) end); cb('ok') end)
RegisterNUICallback('startPolygonCapture', function(data,cb) local zoneType=data.zoneType; CreateThread(function() ST.RunPlacement('zone-polygon',function() return {kind='zone',zoneType=zoneType,placement=ST.CapturePolygon(zoneType)} end) end); cb('ok') end)
RegisterNUICallback('createZone', function(data,cb) local ok,result=lib.callback.await('st_dealership:server:createZone',false,ST.CurrentDealership,data.zone); cb({ok=ok,result=result}) end)
RegisterNUICallback('deleteZone', function(data,cb) local ok,result=lib.callback.await('st_dealership:server:deleteZone',false,ST.CurrentDealership,data.id); cb({ok=ok,result=result}) end)

RegisterCommand('fixnui', function()
    nuiOpen=false; placementActive=false; pcall(lib.hideTextUI); SetNuiFocus(false,false); SendNUIMessage({action='close'})
end,false)
AddEventHandler('onResourceStop',function(resourceName) if resourceName==GetCurrentResourceName() then SetNuiFocus(false,false) end end)
