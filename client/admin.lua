local adminOpen = false

local function closeAdmin()
    if not adminOpen then return end
    adminOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeAdmin' })
end

function ST.OpenAdminConsole()
    local dealerships = lib.callback.await('st_dealership:server:adminGetDealerships', false) or {}
    local catalog = lib.callback.await('st_dealership:server:getFullCatalog', false) or {}
    adminOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openAdmin',
        data = {
            dealerships = dealerships,
            catalog = catalog,
            categories = Config.Market.categories,
            rarities = { 'common', 'uncommon', 'rare', 'exotic' },
            currencySymbol = Config.CurrencySymbol,
            myPlayerId = GetPlayerServerId(PlayerId()),
        },
    })
end

RegisterCommand('admindealership', function()
    local ok = lib.callback.await('st_dealership:server:isDealershipAdmin', false)
    if not ok then
        lib.notify({ title = 'Admin', description = "You don't have permission to do that.", type = 'error' })
        return
    end
    ST.OpenAdminConsole()
end, false) -- restricted does nothing client-side (see client/registry.lua) - the real check is the callback above

CreateThread(function()
    while true do
        Wait(0)
        if adminOpen then
            if IsControlJustPressed(0, 200) then closeAdmin() end -- ESC
        else
            Wait(250)
        end
    end
end)

RegisterNUICallback('adminClose', function(_, cb)
    closeAdmin()
    cb('ok')
end)

RegisterNUICallback('adminRefresh', function(_, cb)
    cb(lib.callback.await('st_dealership:server:adminGetDealerships', false) or {})
end)

RegisterNUICallback('adminSetBalance', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:adminSetBalance', false, data.dealership, data.amount)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('adminAssignOwner', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:adminAssignOwner', false, data.dealership, data.targetId)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('adminDeleteDealership', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:adminDeleteDealership', false, data.dealership)
    cb({ ok = ok, result = result })
end)

-- ---------------------------------------------------------------------------
-- Vehicle catalog management
-- ---------------------------------------------------------------------------

RegisterNUICallback('adminGetCatalog', function(_, cb)
    cb(lib.callback.await('st_dealership:server:getFullCatalog', false) or {})
end)

--- Quick client-side sanity check before bothering the server - doesn't
--- block submission if it comes back invalid, just warns, since a model
--- that isn't streamed on THIS admin's client could still be a perfectly
--- valid addon vehicle their server has installed some other way.
RegisterNUICallback('checkModelValid', function(data, cb)
    local ok, valid = pcall(IsModelInCdimage, GetHashKey(data.model))
    cb({ valid = ok and valid or false })
end)

RegisterNUICallback('adminUpsertCatalogVehicle', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:adminUpsertCatalogVehicle', false, data.vehicle)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('adminRemoveCatalogVehicle', function(data, cb)
    local ok, result = lib.callback.await('st_dealership:server:adminRemoveCatalogVehicle', false, data.model)
    cb({ ok = ok, result = result })
end)

--- "Manage" on a row closes the admin list and opens that dealership's
--- normal Settings screen - admins already have full access there (see
--- ST.HasPermission's admin bypass), so there's no separate edit UI to
--- maintain for branding/zones/lighting.
RegisterNUICallback('adminManageDealership', function(data, cb)
    closeAdmin()
    ST.OpenDealershipUI(data.dealership, 'settings')
    cb('ok')
end)

RegisterNetEvent('st_dealership:client:dealershipDeleted', function(dealershipName)
    ST.TeardownDealershipEntryPoint(dealershipName)
end)

CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/admindealership', 'Open the dealership admin console (admin only)')
end)
