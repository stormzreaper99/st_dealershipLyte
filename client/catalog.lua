ST = ST or {}
ST.CatalogCache = {} -- model -> { label, category, msrp, rarity, source }

local function applyCatalog(entries)
    local cache = {}
    for _, e in ipairs(entries) do
        cache[e.model] = e
    end
    ST.CatalogCache = cache
end

RegisterNetEvent('st_dealership:client:syncCatalog', function(entries)
    applyCatalog(entries)
end)

CreateThread(function()
    local entries = lib.callback.await('st_dealership:server:getFullCatalog', false) or {}
    applyCatalog(entries)
end)
