Shared = Shared or {}

-- Base catalog: one entry per model that CAN appear in dealership inventory.
-- This is the "factory MSRP" and category baseline the market system uses
-- to compute live prices per config/market.lua. Actual inventory rows live
-- in the DB (st_dealership_vehicles) - this table never changes per-vehicle
-- state like mileage/condition/VIN.
Shared.VehicleCatalog = {
    ['sultanrs'] = { label = 'Karin Sultan RS',      category = 'sedan',  msrp = 42000,  rarity = 'common' },
    ['elegy2']   = { label = 'Annis Elegy Retro Custom', category = 'sports', msrp = 65000, rarity = 'uncommon' },
    ['buffalo']  = { label = 'Bravado Buffalo STX',   category = 'muscle', msrp = 38000,  rarity = 'common' },
    ['comet6']   = { label = 'Pfister Comet S2 Cabrio', category = 'sports', msrp = 72000, rarity = 'rare' },
    ['stanier']  = { label = 'Vapid Stanier',         category = 'sedan',  msrp = 21000,  rarity = 'common' },
    ['sultanrsr34'] = { label = '"R34-style" Import',  category = 'sports', msrp = 150000, rarity = 'exotic' },
    ['granger']  = { label = 'Declasse Granger',      category = 'suv',    msrp = 45000,  rarity = 'common' },
    ['bison']    = { label = 'Vapid Bison',           category = 'truck',  msrp = 33000,  rarity = 'common' },
    ['akuma']    = { label = 'Dinka Akuma',           category = 'motorcycle', msrp = 9000, rarity = 'common' },
    ['tampa3']   = { label = 'Declasse Tampa Lowrider', category = 'muscle', msrp = 27000, rarity = 'uncommon' },
}

-- Rarity affects how strongly the market multiplier can swing (see
-- server/market.lua) and starting "days between restock" for auctions.
Shared.RarityWeights = {
    common    = { swingMultiplier = 1.0, restockDays = 1 },
    uncommon  = { swingMultiplier = 1.3, restockDays = 3 },
    rare      = { swingMultiplier = 1.8, restockDays = 7 },
    exotic    = { swingMultiplier = 2.5, restockDays = 21 },
}

function Shared.GetCatalogEntry(model)
    return Shared.VehicleCatalog[model]
end

return Shared
