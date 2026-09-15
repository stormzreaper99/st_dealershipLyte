Config = Config or {}
Config.Dealerships = {
    ['stormline_used'] = {
        label = 'Stormline Auto Sales', type = 'used', job = 'stormline_used', account = 'stormline_used_bank', startingBalance = 50000,
        theme = { primary = '#d6b36a', secondary = '#8e9aad' },
        location = {
            blip = { x = 780.0, y = -1030.0, z = 29.0, sprite = 225, color = 3, scale = 0.8 },
            showroom = { x = 780.0, y = -1030.0, z = 29.0 },
            spawns = {
                { x = 770.0, y = -1020.0, z = 29.0, w = 160.0 },
                { x = 774.0, y = -1024.0, z = 29.0, w = 160.0 },
                { x = 778.0, y = -1028.0, z = 29.0, w = 160.0 },
            },
            testDriveReturn = { x = 780.0, y = -1030.0, z = 29.0, w = 160.0 },
        },
        rules = { marginTarget = 0.18, lowInventoryLuxuryMode = false, requiresInspectionBeforeSale = true },
    },
    ['stormline_lux'] = {
        label = 'Stormline Prestige Motors', type = 'luxury', job = 'stormline_lux', account = 'stormline_lux_bank', startingBalance = 250000,
        theme = { primary = '#c8a86b', secondary = '#b4bdcc' },
        location = {
            blip = { x = -50.0, y = -1100.0, z = 26.0, sprite = 225, color = 5, scale = 0.8 },
            showroom = { x = -50.0, y = -1100.0, z = 26.0 },
            spawns = { { x = -60.0, y = -1105.0, z = 26.0, w = 200.0 } },
            testDriveReturn = { x = -50.0, y = -1100.0, z = 26.0, w = 200.0 },
        },
        rules = { marginTarget = 0.35, lowInventoryLuxuryMode = true, requiresInspectionBeforeSale = true },
    },
    ['stormline_auction'] = {
        label = 'Stormline Auction House', type = 'auction_house', job = 'stormline_auction', account = 'stormline_auction_bank', startingBalance = 0,
        theme = { primary = '#d86b6b', secondary = '#8e9aad' },
        location = {
            blip = { x = 400.0, y = -2200.0, z = 15.0, sprite = 500, color = 1, scale = 0.8 },
            showroom = { x = 400.0, y = -2200.0, z = 15.0 }, spawns = {}, testDriveReturn = nil,
        },
        rules = { marginTarget = 0.0, facilitatesOnly = true },
    },
}
return Config.Dealerships
