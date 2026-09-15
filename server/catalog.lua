local catalogCache = {} -- model -> { label, category, msrp, rarity, source = 'config' | 'custom' }

local function isAdmin(src)
    return Config.AdminPermission and IsPlayerAceAllowed(src, Config.AdminPermission)
end

local function loadBuiltins()
    for model, entry in pairs(Shared.VehicleCatalog) do
        catalogCache[model] = { label = entry.label, category = entry.category, msrp = entry.msrp, rarity = entry.rarity, source = 'config' }
    end
end

local function loadCustom()
    local rows = MySQL.query.await('SELECT * FROM st_dealership_catalog') or {}
    for _, row in ipairs(rows) do
        catalogCache[row.model] = { label = row.label, category = row.category, msrp = tonumber(row.msrp), rarity = row.rarity, source = 'custom' }
    end
end

--- Single source of truth for "what vehicles can a dealership order" -
--- every other server file should call this instead of reading
--- Shared.VehicleCatalog directly, same rule as ST.GetDealership for
--- config vs runtime dealerships.
function ST.GetCatalogEntry(model)
    return catalogCache[model]
end

function ST.GetAllCatalogEntries()
    return catalogCache
end

local function serializeCatalog()
    local out = {}
    for model, entry in pairs(catalogCache) do
        out[#out + 1] = { model = model, label = entry.label, category = entry.category, msrp = entry.msrp, rarity = entry.rarity, source = entry.source }
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

lib.callback.register('st_dealership:server:getFullCatalog', function(src)
    return serializeCatalog()
end)

--- Adds a new orderable vehicle, or edits an existing one (built-in or
--- custom - editing a built-in just overlays a custom row with the same
--- model key, which takes priority since it's applied after the built-ins
--- load). Admin-only, not tied to any specific dealership - the catalog
--- is shared across every dealership on the server.
lib.callback.register('st_dealership:server:adminUpsertCatalogVehicle', function(src, data)
    if not isAdmin(src) then return false, 'not_authorized' end
    if not data or not data.model or data.model == '' then return false, 'invalid_model' end
    if not data.label or data.label == '' then return false, 'invalid_label' end

    local msrp = tonumber(data.msrp)
    if not msrp or msrp <= 0 then return false, 'invalid_msrp' end

    local model = data.model:lower():gsub('%s+', '')
    local category = data.category or 'sedan'
    local rarity = data.rarity or 'common'

    MySQL.insert([[
        INSERT INTO st_dealership_catalog (model, label, category, msrp, rarity, added_by)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE label = VALUES(label), category = VALUES(category), msrp = VALUES(msrp), rarity = VALUES(rarity)
    ]], { model, data.label, category, msrp, rarity, ST.GetPlayerCitizenId(src) })

    catalogCache[model] = { label = data.label, category = category, msrp = msrp, rarity = rarity, source = 'custom' }

    TriggerClientEvent('st_dealership:client:syncCatalog', -1, serializeCatalog())
    return true
end)

--- Only custom (admin-added) entries can be removed - a built-in would
--- just reappear on the next restart since it's loaded from
--- shared/vehicles.lua, so removing it here would be misleading.
lib.callback.register('st_dealership:server:adminRemoveCatalogVehicle', function(src, model)
    if not isAdmin(src) then return false, 'not_authorized' end

    local entry = catalogCache[model]
    if not entry then return false, 'not_found' end
    if entry.source == 'config' then return false, 'cannot_remove_builtin' end

    MySQL.query.await('DELETE FROM st_dealership_catalog WHERE model = ?', { model })
    catalogCache[model] = nil

    TriggerClientEvent('st_dealership:client:syncCatalog', -1, serializeCatalog())
    return true
end)

CreateThread(function()
    loadBuiltins()
    loadCustom()
end)
