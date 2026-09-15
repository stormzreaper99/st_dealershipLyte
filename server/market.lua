local marketCache = {} -- model -> { avgPrice, multiplier, unitsListed, unitsSoldRecent }

function ST.GetMarketPrice(model)
    local cached = marketCache[model]
    if cached then return cached.avgPrice end
    local catalog = ST.GetCatalogEntry(model)
    return catalog and catalog.msrp or nil
end
exports('GetMarketPrice', ST.GetMarketPrice)

function ST.GetMarketSnapshot(model)
    return marketCache[model]
end

--- Recomputes every model's live average price from current supply
--- (units listed in_stock across all dealerships) and recent demand
--- (units sold in the trailing window). Called on a timer and after
--- big inventory swings (auction closes, bulk acquisitions).
function ST.RecalculateMarket()
    -- Two grouped queries for the whole catalog, rather than two awaited
    -- queries per model inside the loop (which was 2N round trips - noticeable
    -- once admins start adding vehicles to the catalog).
    local listedCounts, soldCounts = {}, {}

    for _, row in ipairs(MySQL.query.await(
        "SELECT model, COUNT(*) AS c FROM st_dealership_vehicles WHERE status = 'in_stock' GROUP BY model") or {}) do
        listedCounts[row.model] = tonumber(row.c) or 0
    end

    for _, row in ipairs(MySQL.query.await(
        "SELECT v.model AS model, COUNT(*) AS c FROM st_dealership_contracts c "
        .. "JOIN st_dealership_vehicles v ON v.vin = c.vin "
        .. "WHERE c.created_at >= (NOW() - INTERVAL ? HOUR) GROUP BY v.model",
        { Config.Market.recentSalesWindowHours }) or {}) do
        soldCounts[row.model] = tonumber(row.c) or 0
    end

    for model, catalog in pairs(ST.GetAllCatalogEntries()) do
        local unitsListed = listedCounts[model] or 0
        local unitsSold = soldCounts[model] or 0

        local prior = marketCache[model] or { multiplier = 1.0 }

        -- supply pressure: below baseline pushes price up, above pushes down
        local supplyRatio = Config.Market.baselineSupplyPerModel > 0
            and (unitsListed / Config.Market.baselineSupplyPerModel) or 1.0
        local supplyPressure = Utils.Clamp(1.0 - (supplyRatio - 1.0), 0.5, 1.5)

        -- demand pressure: more recent sales relative to listed stock = hotter
        local demandRatio = unitsListed > 0 and (unitsSold / unitsListed) or (unitsSold > 0 and 2 or 0)
        local demandPressure = Utils.Clamp(1.0 + demandRatio, 1.0, 2.0)

        local targetMultiplier = (supplyPressure * Config.Market.supplyWeight)
            + (demandPressure * Config.Market.demandWeight)

        local rarity = Shared.RarityWeights[catalog.rarity] or Shared.RarityWeights.common
        local maxSwing = Config.Market.maxSwingPercentPerTick * rarity.swingMultiplier

        local newMultiplier = Utils.Clamp(
            prior.multiplier + Utils.Clamp(targetMultiplier - prior.multiplier, -maxSwing, maxSwing),
            Config.Market.minMarketMultiplier, Config.Market.maxMarketMultiplier
        )

        local avgPrice = Utils.Round(catalog.msrp * newMultiplier)

        marketCache[model] = {
            avgPrice = avgPrice, multiplier = newMultiplier,
            unitsListed = unitsListed, unitsSoldRecent = unitsSold,
        }

        MySQL.insert([[
            INSERT INTO st_dealership_market (model, avg_price, multiplier, units_listed, units_sold_recent)
            VALUES (?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE avg_price = VALUES(avg_price), multiplier = VALUES(multiplier),
                units_listed = VALUES(units_listed), units_sold_recent = VALUES(units_sold_recent)
        ]], { model, avgPrice, newMultiplier, unitsListed, unitsSold })
    end
end

--- Dealer Intelligence dashboard data: trending/low-supply/oversupply lists
--- grouped by category, for the management NUI.
lib.callback.register('st_dealership:server:getMarketIntel', function(src)
    local trending, lowSupply, oversupply, categoryTrend = {}, {}, {}, {}

    for model, snap in pairs(marketCache) do
        local catalog = ST.GetCatalogEntry(model)
        if catalog then
            categoryTrend[catalog.category] = (categoryTrend[catalog.category] or 0) + (snap.multiplier - 1.0)

            if snap.unitsSoldRecent >= 3 then
                table.insert(trending, { model = model, label = catalog.label, unitsSold = snap.unitsSoldRecent })
            end
            if snap.unitsListed <= 3 then
                table.insert(lowSupply, { model = model, label = catalog.label, unitsListed = snap.unitsListed })
            end
            if snap.unitsListed >= Config.Market.baselineSupplyPerModel * 3 then
                table.insert(oversupply, { model = model, label = catalog.label, unitsListed = snap.unitsListed })
            end
        end
    end

    return { trending = trending, lowSupply = lowSupply, oversupply = oversupply, categoryTrend = categoryTrend }
end)

CreateThread(function()
    Wait(2000)
    ST.RecalculateMarket()
    while true do
        Wait(Config.MarketIntervalMs)
        ST.RecalculateMarket()
    end
end)
