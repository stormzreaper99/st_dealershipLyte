local marketCache = {}

function ST.GetMarketPrice(model)
    local cached = marketCache[model]
    if cached then return cached.avgPrice end
    local catalog = ST.GetCatalogEntry(model)
    return catalog and catalog.msrp or nil
end
exports('GetMarketPrice', ST.GetMarketPrice)
function ST.GetMarketSnapshot(model) return marketCache[model] end

function ST.RecalculateMarket()
    local listedCounts = {}
    for _, row in ipairs(MySQL.query.await("SELECT model, COUNT(*) AS c FROM st_dealership_vehicles WHERE status = 'in_stock' GROUP BY model") or {}) do
        listedCounts[row.model] = tonumber(row.c) or 0
    end
    for model, catalog in pairs(ST.GetAllCatalogEntries()) do
        local unitsListed = listedCounts[model] or 0
        local prior = marketCache[model] or { multiplier = 1.0 }
        local supplyRatio = Config.Market.baselineSupplyPerModel > 0 and (unitsListed / Config.Market.baselineSupplyPerModel) or 1.0
        local supplyPressure = Utils.Clamp(1.0 - (supplyRatio - 1.0), 0.5, 1.5)
        local targetMultiplier = supplyPressure * Config.Market.supplyWeight
        local rarity = Shared.RarityWeights[catalog.rarity] or Shared.RarityWeights.common
        local maxSwing = Config.Market.maxSwingPercentPerTick * rarity.swingMultiplier
        local newMultiplier = Utils.Clamp(prior.multiplier + Utils.Clamp(targetMultiplier - prior.multiplier, -maxSwing, maxSwing), Config.Market.minMarketMultiplier, Config.Market.maxMarketMultiplier)
        local avgPrice = Utils.Round(catalog.msrp * newMultiplier)
        marketCache[model] = { avgPrice = avgPrice, multiplier = newMultiplier, unitsListed = unitsListed }
        MySQL.insert([[
            INSERT INTO st_dealership_market (model, avg_price, multiplier, units_listed)
            VALUES (?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE avg_price = VALUES(avg_price), multiplier = VALUES(multiplier), units_listed = VALUES(units_listed)
        ]], { model, avgPrice, newMultiplier, unitsListed })
    end
end

lib.callback.register('st_dealership:server:getMarketIntel', function(src)
    local lowSupply, oversupply = {}, {}
    for model, snap in pairs(marketCache) do
        local catalog = ST.GetCatalogEntry(model)
        if catalog then
            if snap.unitsListed <= 3 then lowSupply[#lowSupply + 1] = { model = model, label = catalog.label, unitsListed = snap.unitsListed } end
            if snap.unitsListed >= Config.Market.baselineSupplyPerModel * 3 then oversupply[#oversupply + 1] = { model = model, label = catalog.label, unitsListed = snap.unitsListed } end
        end
    end
    return { lowSupply = lowSupply, oversupply = oversupply }
end)

CreateThread(function()
    Wait(2000)
    ST.RecalculateMarket()
    while true do Wait(Config.MarketIntervalMs); ST.RecalculateMarket() end
end)
