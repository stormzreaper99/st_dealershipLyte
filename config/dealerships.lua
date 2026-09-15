Config = Config or {}
Config.Dealerships = {

    ['stormline_used'] = {
        label      = 'Stormline Auto Sales',
        type       = 'used',              -- used | new | luxury | performance | moto | truck | rv | boat | aircraft | auction_house | rental
        job        = 'stormline_used',     -- qbx_core job name; departments map to job grades
        account    = 'stormline_used_bank', -- oxmysql-tracked dealership bank account key
        startingBalance = 50000,
        location = {
            blip     = { x = 780.0, y = -1030.0, z = 29.0, sprite = 225, color = 3, scale = 0.8 },
            showroom = { x = 780.0, y = -1030.0, z = 29.0 },
            spawns   = {
                { x = 770.0, y = -1020.0, z = 29.0, w = 160.0 },
                { x = 774.0, y = -1024.0, z = 29.0, w = 160.0 },
                { x = 778.0, y = -1028.0, z = 29.0, w = 160.0 },
            },
            testDriveReturn = { x = 780.0, y = -1030.0, z = 29.0, w = 160.0 },
        },
        -- Business rules that flavor how the dealership behaves (used by
        -- server/market.lua and server/sales.lua to weight decisions).
        rules = {
            marginTarget   = 0.18,   -- used dealer: buy cheap, repair, sell ~18% over cost
            lowInventoryLuxuryMode = false,
            requiresInspectionBeforeSale = true,
            reputationWeight = { pricing = 1.2, honesty = 1.0, quality = 1.0 },
        },
    },

    ['stormline_lux'] = {
        label      = 'Stormline Prestige Motors',
        type       = 'luxury',
        job        = 'stormline_lux',
        account    = 'stormline_lux_bank',
        startingBalance = 250000,
        location = {
            blip     = { x = -50.0, y = -1100.0, z = 26.0, sprite = 225, color = 5, scale = 0.8 },
            showroom = { x = -50.0, y = -1100.0, z = 26.0 },
            spawns   = {
                { x = -60.0, y = -1105.0, z = 26.0, w = 200.0 },
            },
            testDriveReturn = { x = -50.0, y = -1100.0, z = 26.0, w = 200.0 },
        },
        rules = {
            marginTarget = 0.35,
            lowInventoryLuxuryMode = true,        -- keep stock low, prices high
            requiresInspectionBeforeSale = true,
            reputationWeight = { pricing = 0.6, honesty = 1.4, quality = 1.6 },
        },
    },

    ['stormline_auction'] = {
        label      = 'Stormline Auction House',
        type       = 'auction_house',
        job        = 'stormline_auction',
        account    = 'stormline_auction_bank',
        startingBalance = 0,
        location = {
            blip     = { x = 400.0, y = -2200.0, z = 15.0, sprite = 500, color = 1, scale = 0.8 },
            showroom = { x = 400.0, y = -2200.0, z = 15.0 },
            spawns   = {},
            testDriveReturn = nil,
        },
        rules = {
            marginTarget = 0.0,          -- doesn't own inventory long-term
            facilitatesOnly = true,      -- auction house never "owns" stock for retail
            reputationWeight = { pricing = 1.0, honesty = 1.2, quality = 0.8 },
        },
    },
}

return Config.Dealerships
