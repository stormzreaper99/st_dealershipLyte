-- ---------------------------------------------------------------------------
-- VIN allocation
-- ---------------------------------------------------------------------------

--- `st_dealership_vehicles.vin` is UNIQUE, so a collision used to mean a
--- silently dropped insert. 33^8 makes one unlikely, not impossible - this
--- checks before using it and retries a handful of times.
function ST.GenerateUniqueVIN()
    for _ = 1, 10 do
        local vin = Utils.GenerateVIN()
        local existing = MySQL.scalar.await('SELECT 1 FROM st_dealership_vehicles WHERE vin = ?', { vin })
        if not existing then return vin end
    end
    print('[st_dealership] could not allocate a unique VIN after 10 attempts')
    return nil
end

-- ---------------------------------------------------------------------------
-- Inspection
-- ---------------------------------------------------------------------------

--- Generates a condition report for a used vehicle. Newer / lower-mileage
--- vehicles roll higher base condition; higher mileage and accident count
--- drag it down. Factory-ordered/new vehicles should just call
--- ST.NewVehicleCondition() instead.
local function rollUsedCondition(mileage, accidentCount)
    local conditions = {}
    -- base condition falls off with mileage: ~100 at 0mi, ~55 at 150k mi
    local mileagePenalty = math.min(45, (mileage / 150000) * 45)
    for _, part in ipairs(Config.ConditionParts) do
        local base = 100 - mileagePenalty
        local variance = math.random(-15, 8)
        local accidentPenalty = accidentCount * math.random(3, 12)
        conditions[part] = Utils.Clamp(Utils.Round(base + variance - accidentPenalty), 5, 100)
    end
    return conditions
end

function ST.NewVehicleCondition()
    local conditions = {}
    for _, part in ipairs(Config.ConditionParts) do
        conditions[part] = 100
    end
    return conditions
end

--- Runs (or re-runs) an inspection on a VIN already in inventory. Service
--- department only (perm: 'inspect').
function ST.InspectVehicle(src, vin)
    local dealershipName, ok = ST.ResolveDealershipForVin(vin)
    if not ok then return false, 'not_found' end
    if not ST.HasPermission(src, dealershipName, 'inspect') then return false, 'no_permission' end

    local row = MySQL.single.await('SELECT mileage, accident_history FROM st_dealership_vehicles WHERE vin = ?', { vin })
    if not row then return false, 'not_found' end

    local accidents = json.decode(row.accident_history or '[]') or {}
    local conditions = rollUsedCondition(row.mileage, #accidents)

    MySQL.update('UPDATE st_dealership_vehicles SET condition_json = ?, inspected = 1 WHERE vin = ?',
        { json.encode(conditions), vin })

    ST.LogVehicleHistory(vin, 'inspected', { conditions = conditions })

    return true, conditions
end

function ST.ResolveDealershipForVin(vin)
    local row = MySQL.single.await('SELECT dealership FROM st_dealership_vehicles WHERE vin = ?', { vin })
    if not row then return nil, false end
    return row.dealership, true
end

-- ---------------------------------------------------------------------------
-- Acquisition
-- ---------------------------------------------------------------------------

--- Adds a vehicle row to a dealership's inventory. `source` one of
--- factory_order | auction | trade_in | repo | wholesale_in.
--- `overrides` may set mileage, previousOwners, titleStatus, accidents, etc.
function ST.AcquireVehicle(dealershipName, model, source, overrides)
    overrides = overrides or {}
    local catalog = ST.GetCatalogEntry(model)
    if not catalog then return false, 'unknown_model' end

    local vin = ST.GenerateUniqueVIN()
    if not vin then return false, 'vin_generation_failed' end

    local mileage = overrides.mileage or (source == 'factory_order' and 0 or math.random(500, 95000))
    local isUsed = mileage > 0
    local conditions = overrides.conditions or (isUsed and rollUsedCondition(mileage, overrides.accidentCount or 0) or ST.NewVehicleCondition())
    local avgCondition = Utils.AverageCondition(conditions)

    local purchaseCost = overrides.purchaseCost or Utils.Round(catalog.msrp * (isUsed and 0.55 or 0.85))
    local marketPrice = ST.GetMarketPrice(model) or catalog.msrp
    local conditionFactor = 0.6 + (avgCondition / 100) * 0.4 -- 60%-100% of market value based on condition
    local askingPrice = Utils.Round(marketPrice * conditionFactor)
    local minPrice = Utils.Round(math.max(purchaseCost * 1.02, askingPrice * 0.85))

    local insertedId = MySQL.insert.await([[
        INSERT INTO st_dealership_vehicles
            (vin, dealership, model, mileage, condition_json, purchase_cost, asking_price, min_price,
             acquisition_source, previous_owners, accident_history, title_status, financing_eligible, status, inspected)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'in_stock', ?)
    ]], {
        vin, dealershipName, model, mileage, json.encode(conditions), purchaseCost, askingPrice, minPrice,
        source, overrides.previousOwners or (isUsed and math.random(1, 3) or 0),
        json.encode(overrides.accidents or {}), overrides.titleStatus or 'clean',
        avgCondition >= 40 and 1 or 0, source ~= 'factory_order' and 1 or 0,
    })

    -- `vin` carries a UNIQUE index, so a failed insert here means the row
    -- genuinely didn't land - returning success anyway would have the
    -- caller (a factory delivery, a trade-in) believe stock exists that
    -- doesn't, and in the factory-order case the dealership was already
    -- charged for it.
    if not insertedId then
        return false, 'insert_failed'
    end

    if overrides.skipPayment then
        -- Caller already deducted this (factory orders charge at order
        -- time, not at delivery - see server/factorydelivery.lua) - doing
        -- it again here would double-charge the dealership.
    elseif not ST.AdjustBalance(dealershipName, -purchaseCost, true, 'inventory-acquisition') then
        -- allow negative here; management is expected to fund acquisitions,
        -- the UI should warn but not hard-block a factory order in flight
    end

    ST.LogVehicleHistory(vin, 'acquired', { source = source, dealership = dealershipName, cost = purchaseCost })

    return true, {
        vin = vin, model = model, mileage = mileage, condition = avgCondition,
        purchaseCost = purchaseCost, askingPrice = askingPrice, minPrice = minPrice,
    }
end
exports('AcquireVehicle', ST.AcquireVehicle)

--- Manual re-listing / price change by an Inventory Manager (perm: 'set_pricing')
function ST.AdjustVehiclePrice(src, vin, newAskingPrice)
    local dealershipName = ST.ResolveDealershipForVin(vin)
    if not dealershipName then return false, 'not_found' end
    if not ST.HasPermission(src, dealershipName, 'set_pricing') then return false, 'no_permission' end

    -- Unvalidated before: a negative or non-numeric price would go straight
    -- into the column and make the vehicle pay the buyer.
    newAskingPrice = math.floor(tonumber(newAskingPrice) or 0)
    if newAskingPrice <= 0 then return false, 'invalid_price' end

    -- Asking below the floor makes min_price meaningless everywhere else,
    -- so the floor moves with it rather than being silently ignored.
    MySQL.update('UPDATE st_dealership_vehicles SET asking_price = ?, min_price = LEAST(min_price, ?) WHERE vin = ?',
        { newAskingPrice, newAskingPrice, vin })
    return true
end
exports('AdjustVehiclePrice', ST.AdjustVehiclePrice)

function ST.GetDealershipInventory(dealershipName, statusFilter)
    local query = 'SELECT * FROM st_dealership_vehicles WHERE dealership = ?'
    local params = { dealershipName }
    if statusFilter then
        query = query .. ' AND status = ?'
        table.insert(params, statusFilter)
    end
    return MySQL.query.await(query, params) or {}
end
exports('GetDealershipInventory', ST.GetDealershipInventory)

function ST.GetVehicleByVin(vin)
    return MySQL.single.await('SELECT * FROM st_dealership_vehicles WHERE vin = ?', { vin })
end
exports('GetVehicleByVin', ST.GetVehicleByVin)

-- ---------------------------------------------------------------------------
-- Callbacks
-- ---------------------------------------------------------------------------

lib.callback.register('st_dealership:server:getInventory', function(src, dealershipName)
    return ST.GetDealershipInventory(dealershipName, 'in_stock')
end)

lib.callback.register('st_dealership:server:getVehicle', function(src, vin)
    return ST.GetVehicleByVin(vin)
end)

lib.callback.register('st_dealership:server:inspectVehicle', function(src, vin)
    local ok, result = ST.InspectVehicle(src, vin)
    return ok, result
end)

--- The 'trade_in' exemption that used to live here let ANY player call
--- this with source='trade_in' and add free stock to any dealership.
--- Trade-ins never needed it: they go through
--- st_dealership:server:acceptTradeIn (server/trades.lua), which calls
--- ST.AcquireVehicle directly after validating the offer.
---
--- `overrides` is also no longer passed through from the client - it could
--- set purchaseCost, mileage, condition and title status arbitrarily.
lib.callback.register('st_dealership:server:acquireVehicle', function(src, dealershipName, model, source)
    if not ST.HasPermission(src, dealershipName, 'purchase_inventory') then
        return false, 'no_permission'
    end

    local allowedSources = { factory_order = true, auction = true, wholesale_in = true }
    if not allowedSources[source] then return false, 'invalid_source' end

    return ST.AcquireVehicle(dealershipName, model, source)
end)

lib.callback.register('st_dealership:server:adjustPrice', function(src, vin, newAskingPrice)
    return ST.AdjustVehiclePrice(src, vin, newAskingPrice)
end)
