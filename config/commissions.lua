Config = Config or {}

Config.Commissions = {
    baseRatePercent = 5.0,   -- % of sale price paid to salesperson

    bonuses = {
        highSatisfaction   = 1.0,   -- customer rated deal 4-5 stars
        monthlyTargetHit   = 1.0,   -- salesperson met monthly unit target
        difficultSale      = 2.0,   -- vehicle was 60+ days on lot ("slow seller")
        financingDeal      = 1.0,   -- sale included dealer financing
        tradeInIncluded    = 0.5,
    },

    monthlyUnitTarget = 10,        -- units sold per month to trigger monthlyTargetHit

    -- Owners/management can override per-dealership via the in-game
    -- management menu; overrides are persisted to `st_dealership_settings`.
    allowOwnerOverride = true,
}

return Config.Commissions
