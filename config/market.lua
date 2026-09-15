Config = Config or {}

Config.Market = {
    baselineSupplyPerModel = 6,
    maxSwingPercentPerTick = 0.05,
    supplyWeight = 1.0,
    minMarketMultiplier = 0.5,
    maxMarketMultiplier = 3.0,
    categories = { 'sedan', 'suv', 'sports', 'truck', 'muscle', 'super', 'motorcycle', 'offroad', 'van' },
}

return Config.Market
