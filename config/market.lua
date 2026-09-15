Config = Config or {}

Config.Market = {
    -- Baseline supply the demand curve is centered on. If the server-wide
    -- count of a model's listed inventory is below this, price trends up;
    -- above it, price trends down.
    baselineSupplyPerModel = 6,

    -- Max % a model's average price can move per market tick (30 min default)
    maxSwingPercentPerTick = 0.05,

    -- How strongly recent sales pull price up (demand) vs. how strongly
    -- current unsold supply pulls price down (oversupply)
    demandWeight   = 0.6,
    supplyWeight   = 0.4,

    -- "Recent sales" window in hours used to gauge demand
    recentSalesWindowHours = 48,

    -- Rarity multiplier floor/ceiling so rare cars don't spiral infinitely
    minMarketMultiplier = 0.5,
    maxMarketMultiplier = 3.0,

    -- Category-level trend tags shown on the Dealer Intelligence dashboard.
    -- Purely informational; computed live from sales/listing data.
    categories = { 'sedan', 'suv', 'sports', 'truck', 'muscle', 'super', 'motorcycle', 'offroad', 'van' },
}

return Config.Market
