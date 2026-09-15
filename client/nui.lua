local nuiOpen = false
local placementActive = false

-- ---------------------------------------------------------------------------
-- PLACEMENT LIFECYCLE
--
-- Every in-world placement tool (zone point, zone polygon, light) used to
-- hide the UI, drop focus, run its own key loop, then re-grab focus and
-- fire its own NUI message - each one hand-rolling the same sequence with
-- no error handling. If anything between "focus off" and "UI visible
-- again" failed, the player was left with a mouse cursor, no interface,
-- and no way out: ESC is handled inside the NUI page, which was hidden.
--
-- All three now go through here instead. Focus is guaranteed to be
-- restored exactly once, a Lua error inside the tool can't strand it, and
-- placementActive can't get stuck on.
-- ---------------------------------------------------------------------------

function ST.IsPlacementActive()
    return placementActive
end

--- Runs `fn` (an in-world capture tool) with the UI hidden, then restores
--- the UI with whatever `fn` returned as the placement payload.
function ST.RunPlacement(label, fn)
    if placementActive then return end
    placementActive = true

    SendNUIMessage({ action = 'close' })
    SetNuiFocus(false, false)

    local ok, payload = pcall(fn)

    if not ok then
        print(('[st_dealership] placement tool "%s" errored: %s'):format(label, tostring(payload)))
        payload = nil
        lib.notify({
            title = 'Placement',
            description = 'Something went wrong placing that - the menu has been restored.',
            type = 'error',
        })
    end

    -- Always tidy up the prompt, whatever happened inside the tool.
    pcall(lib.hideTextUI)

    placementActive = false

    if not nuiOpen then
        -- The UI was closed underneath us. Taking focus now would put a
        -- cursor on screen with nothing behind it - exactly the stuck
        -- state this whole wrapper exists to prevent.
        SetNuiFocus(false, false)
        return
    end

    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'placementResult', data = payload })
end
local lastTradeInVehicle = nil -- netId of the vehicle currently up for trade-in appraisal

local function closeNUI()
    if not nuiOpen then return end
    nuiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

--- Builds the catalog list the "Order From Factory" panel needs, without a
--- round trip to the server (Shared.VehicleCatalog is a shared script).
local function buildCatalog()
    -- ST.CatalogCache (client/catalog.lua) is the merged built-in + admin-
    -- added list; falls back to the raw built-ins only in the extremely
    -- unlikely case this NUI opens before that cache's own startup sync
    -- has landed.
    local source = (ST.CatalogCache and next(ST.CatalogCache)) and ST.CatalogCache or Shared.VehicleCatalog
    local list = {}
    for model, entry in pairs(source) do
        list[#list + 1] = {
            model = model, label = entry.label, category = entry.category,
            msrp = entry.msrp, rarity = entry.rarity,
        }
    end
    return list
end

local function buildZoneTypes()
    local list = {}
    for key, def in pairs(Config.ZoneTypes) do
        list[#list + 1] = { key = key, label = def.label, shape = def.shape, icon = def.icon, interactable = def.interactable or false }
    end
    return list
end

local function buildLightTypes()
    local list = {}
    for key, def in pairs(Config.LightTypes) do
        list[#list + 1] = {
            key = key, label = def.label, hasDirection = def.hasDirection,
            defaultRange = def.defaultRange, defaultBrightness = def.defaultBrightness, defaultRadius = def.defaultRadius,
        }
    end
    return list
end

--- `initialView` optionally jumps straight to a view (e.g. 'dashboard' from
--- the management_pc target) instead of opening on the showroom.
function ST.OpenDealershipUI(dealershipName, initialView)
    local dealership = ST.ResolveDealership(dealershipName)
    if not dealership then return end

    ST.CurrentDealership = dealershipName

    local meta = lib.callback.await('st_dealership:server:getDealershipMeta', false, dealershipName)
    if not meta then
        -- Narrow race: the dealership was deleted server-side in the gap
        -- between that happening and this client's teardown event
        -- arriving. Bail out cleanly instead of indexing into nil below.
        lib.notify({ title = 'Dealership', description = 'This dealership no longer exists.', type = 'error' })
        return
    end
    local perms = lib.callback.await('st_dealership:server:getPermissions', false, dealershipName)

    nuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        data = {
            dealership = { name = dealershipName, label = meta.label, type = meta.type, balance = meta.balance },
            permissions = perms,
            citizenId = ST.GetLocalCitizenId(),
            currencySymbol = Config.CurrencySymbol,
            aging = Config.Aging,
            financingTerms = Config.Financing.terms,
            catalog = buildCatalog(),
            zoneTypes = buildZoneTypes(),
            lightTypes = buildLightTypes(),
            staffGrades = Config.StaffGrades,
            initialView = initialView,
        },
    })
end

CreateThread(function()
    while true do
        Wait(0)
        if nuiOpen and not placementActive then
            if IsControlJustPressed(0, 200) then -- ESC
                closeNUI()
            end
        else
            Wait(250)
        end
    end
end)

RegisterNUICallback('close', function(_, cb)
    closeNUI()
    cb('ok')
end)

-- ---------------------------------------------------------------------------
-- Showroom / negotiation / trade-in / test drive
-- ---------------------------------------------------------------------------

RegisterNUICallback('getInventory', function(data, cb)
    cb(lib.callback.await('st_dealership:server:getInventory', false, ST.CurrentDealership) or {})
end)

RegisterNUICallback('getVehicle', function(data, cb)
    cb(lib.callback.await('st_dealership:server:getVehicle', false, data.vin))
end)

RegisterNUICallback('inspectVehicle', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:inspectVehicle', false, data.vin)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('evaluateOffer', function(data, cb)
    cb(lib.callback.await('st_dealership:server:evaluateOffer', false, data.vin, tonumber(data.offer)))
end)

RegisterNUICallback('quoteFinancing', function(data, cb)
    cb(lib.callback.await('st_dealership:server:quoteFinancing', false, ST.GetLocalCitizenId(),
        tonumber(data.price), tonumber(data.downPayment), tonumber(data.termMonths)))
end)

RegisterNUICallback('kioskPurchase', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:kioskPurchase', false, data.vin, tonumber(data.finalPrice), data.dealOptions)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('employeeSell', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:sellVehicle', false, data.vin, data.buyerCitizenId, tonumber(data.finalPrice), data.dealOptions)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('adjustPrice', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:adjustPrice', false, data.vin, tonumber(data.price))
    cb({ ok = ok, result = result })
end)

--- `overrides` is deliberately not forwarded any more - it let the client
--- dictate purchase cost, mileage, condition and title status.
RegisterNUICallback('acquireVehicle', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:acquireVehicle', false, ST.CurrentDealership, data.model, data.source or 'factory_order')
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('submitFactoryOrder', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:submitFactoryOrder', false, ST.CurrentDealership, data.model)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('getPendingOrders', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getPendingOrders', false, ST.CurrentDealership) or {})
end)

--- Runs in its own thread since the photo shoot blocks (waits for
--- Enter/Backspace, then a screenshot upload) before it resolves - the
--- flow reopens the dealership UI itself once done, so this cb is just
--- an ack that the shoot started.
RegisterNUICallback('startVehiclePhoto', function(data, cb)
    local dealershipName = ST.CurrentDealership
    CreateThread(function()
        ST.StartVehiclePhotoShoot(dealershipName, data.vin, data.model)
    end)
    cb('ok')
end)

RegisterNUICallback('appraiseTradeIn', function(data, cb)
    local info = ST.GetCurrentVehicleInfo()
    if not info then
        cb({ error = 'not_in_vehicle' })
        return
    end
    lastTradeInVehicle = info.netId
    cb(lib.callback.await('st_dealership:server:appraiseTradeIn', false, ST.CurrentDealership, info))
end)

RegisterNUICallback('acceptTradeIn', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:acceptTradeIn', false, data.offerId)
    if ok and lastTradeInVehicle then
        local veh = NetworkGetEntityFromNetworkId(lastTradeInVehicle)
        if veh and veh ~= 0 and DoesEntityExist(veh) then DeleteEntity(veh) end
        lastTradeInVehicle = nil
    end
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('startTestDrive', function(data, cb)
    local vehicle = lib.callback.await('st_dealership:server:getVehicle', false, data.vin)
    if vehicle then
        closeNUI()
        ST.StartTestDrive(ST.CurrentDealership, vehicle)
    end
    cb('ok')
end)

RegisterNUICallback('endTestDrive', function(_, cb)
    ST.EndTestDrive('manual')
    cb('ok')
end)

-- ---------------------------------------------------------------------------
-- Dashboard
-- ---------------------------------------------------------------------------

RegisterNUICallback('getAgingReport', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getAgingReport', false, ST.CurrentDealership) or {})
end)

RegisterNUICallback('clearanceSale', function(data, cb)
    cb(lib.callback.await('st_dealership:server:clearanceSale', false, ST.CurrentDealership, tonumber(data.days), tonumber(data.percent)))
end)

RegisterNUICallback('getMarketIntel', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getMarketIntel', false))
end)

RegisterNUICallback('getLeaderboard', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getLeaderboard', false, ST.CurrentDealership) or {})
end)

RegisterNUICallback('getReputation', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getReputation', false, ST.CurrentDealership))
end)

RegisterNUICallback('getActiveLoans', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getActiveLoans', false, ST.CurrentDealership) or {})
end)

RegisterNUICallback('pingFinancedVehicle', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:pingFinancedVehicle', false, ST.CurrentDealership, data.loanId)
    if ok and result and result.coords then
        SetNewWaypoint(result.coords.x, result.coords.y)
    end
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('getRepoTracking', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getRepoTracking', false, ST.CurrentDealership) or {})
end)

RegisterNUICallback('completeRepo', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:completeRepo', false, ST.CurrentDealership, data.loanId)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('submitFinancingRequest', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:submitFinancingRequest', false, ST.CurrentDealership, data.vin, data.finalPrice, data.downPayment, data.termMonths)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('getFinancingRequests', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getFinancingRequests', false, ST.CurrentDealership) or {})
end)

RegisterNUICallback('approveFinancingRequest', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:approveFinancingRequest', false, ST.CurrentDealership, data.requestId)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('denyFinancingRequest', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:denyFinancingRequest', false, ST.CurrentDealership, data.requestId)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('getOpenAuctions', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getOpenAuctions', false) or {})
end)

RegisterNUICallback('placeBid', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:placeBid', false, tonumber(data.auctionId), ST.CurrentDealership, tonumber(data.amount))
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('sendToAuction', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:sendToAuction', false, ST.CurrentDealership, data.vin, data.startingBid, data.durationMinutes)
    cb({ ok = ok, result = result })
end)

-- ---------------------------------------------------------------------------
-- Dealer-to-dealer trading
-- ---------------------------------------------------------------------------

RegisterNUICallback('getAllDealershipNames', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getAllDealershipNames', false, ST.CurrentDealership) or {})
end)

RegisterNUICallback('submitTransferOffer', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:submitTransferOffer', false, ST.CurrentDealership, data.toDealership, data.vin, data.cashAdjustment)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('getIncomingTransfers', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getIncomingTransfers', false, ST.CurrentDealership) or {})
end)

RegisterNUICallback('getOutgoingTransfers', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getOutgoingTransfers', false, ST.CurrentDealership) or {})
end)

RegisterNUICallback('acceptTransferOffer', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:acceptTransferOffer', false, ST.CurrentDealership, data.transferId)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('declineTransferOffer', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:declineTransferOffer', false, ST.CurrentDealership, data.transferId)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('cancelTransferOffer', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:cancelTransferOffer', false, ST.CurrentDealership, data.transferId)
    cb({ ok = ok, result = result })
end)

-- ---------------------------------------------------------------------------
-- Staff (hire/fire) - Dealership Ops tab
-- ---------------------------------------------------------------------------

RegisterNUICallback('getOnlineStaff', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getOnlineStaff', false, ST.CurrentDealership) or {})
end)

RegisterNUICallback('hireStaff', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:hireStaff', false, ST.CurrentDealership, data.targetId, data.grade)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('fireStaff', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:fireStaff', false, ST.CurrentDealership, data.targetId)
    cb({ ok = ok, result = result })
end)

-- ---------------------------------------------------------------------------
-- Display vehicles
-- ---------------------------------------------------------------------------

RegisterNUICallback('getDisplayZones', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getDisplayZones', false, ST.CurrentDealership) or {})
end)

RegisterNUICallback('assignDisplayVehicle', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:assignDisplayVehicle', false, ST.CurrentDealership, data.zoneId, data.vin)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('clearDisplayVehicle', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:clearDisplayVehicle', false, ST.CurrentDealership, data.zoneId)
    cb({ ok = ok, result = result })
end)

-- ---------------------------------------------------------------------------
-- Settings: branding
-- ---------------------------------------------------------------------------

RegisterNUICallback('getBranding', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getBranding', false, ST.CurrentDealership))
end)

RegisterNUICallback('updateBranding', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:updateBranding', false, ST.CurrentDealership, data.branding)
    cb({ ok = ok, result = result })
end)

-- ---------------------------------------------------------------------------
-- Settings: lighting
-- ---------------------------------------------------------------------------

RegisterNUICallback('getLights', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getLights', false, ST.CurrentDealership) or {})
end)

--- Kicks off the in-world placement tool. Runs in its own thread since the
--- tool blocks (frame loop) until the player confirms/cancels; the actual
--- result arrives later via a 'placementResult' NUI message, not this cb.
RegisterNUICallback('startLightPlacement', function(data, cb)
    local mode, lightType, lightId = data.mode, data.lightType, data.lightId
    CreateThread(function()
        ST.RunPlacement('light', function()
            return {
                kind = 'light', mode = mode, lightType = lightType, lightId = lightId,
                placement = ST.RunLightPlacementTool(),
            }
        end)
    end)
    cb('ok')
end)

RegisterNUICallback('createLight', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:createLight', false, ST.CurrentDealership, data.light)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('updateLight', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:updateLight', false, ST.CurrentDealership, data.id, data.light)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('deleteLight', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:deleteLight', false, ST.CurrentDealership, data.id)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('locateLight', function(data, cb)
    ST.HighlightLight(data.id, 6)
    cb('ok')
end)

-- ---------------------------------------------------------------------------
-- Settings: zones
-- ---------------------------------------------------------------------------

RegisterNUICallback('getZones', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getZones', false, ST.CurrentDealership) or {})
end)

RegisterNUICallback('startZoneCapture', function(data, cb)
    local zoneType = data.zoneType
    CreateThread(function()
        ST.RunPlacement('zone-point', function()
            return { kind = 'zone', zoneType = zoneType, placement = ST.CaptureZonePoint(zoneType) }
        end)
    end)
    cb('ok')
end)

RegisterNUICallback('startPolygonCapture', function(data, cb)
    local zoneType = data.zoneType
    CreateThread(function()
        ST.RunPlacement('zone-polygon', function()
            return { kind = 'zone', zoneType = zoneType, placement = ST.CapturePolygon(zoneType) }
        end)
    end)
    cb('ok')
end)

RegisterNUICallback('createZone', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:createZone', false, ST.CurrentDealership, data.zone)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('deleteZone', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:deleteZone', false, ST.CurrentDealership, data.id)
    cb({ ok = ok, result = result })
end)


-- ---------------------------------------------------------------------------
-- Recovery
--
-- A last-resort way out if the interface ever ends up focused-but-invisible
-- again (from this resource or any other). Also fires automatically if the
-- resource stops mid-placement, which would otherwise leave the player
-- holding a cursor with the script no longer running to release it.
-- ---------------------------------------------------------------------------
local function forceReleaseNui()
    nuiOpen = false
    placementActive = false
    pcall(lib.hideTextUI)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    SendNUIMessage({ action = 'closeAdmin' })
end

RegisterCommand('fixnui', function()
    forceReleaseNui()
    lib.notify({ title = 'Dealership', description = 'Interface released.', type = 'inform' })
end, false)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        SetNuiFocus(false, false)
    end
end)

CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/fixnui', 'Release a stuck dealership interface (cursor on screen, no menu)')
end)
