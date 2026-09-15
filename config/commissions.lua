Config = Config or {}

Config.Commissions = {
    baseRatePercent = 5.0,
    bonuses = {
        highSatisfaction = 1.0,
        monthlyTargetHit = 1.0,
        financingDeal = 1.0,
        tradeInIncluded = 0.5,
    },
    monthlyUnitTarget = 10,
    allowOwnerOverride = true,
}

return Config.Commissions
