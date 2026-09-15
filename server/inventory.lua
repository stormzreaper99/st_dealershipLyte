function ST.GenerateUniqueVIN()
    for _ = 1, 10 do
        local vin = Utils.GenerateVIN()
        if not MySQL.scalar.await('SELECT 1 FROM st_dealership_vehicles WHERE vin = ?', { vin }) then return vin end
    end
    print('[st_dealership] could not allocate a unique VIN after 10 attempts')
    return nil
end

local function rollUsedCondition(mileage, accidentCount)
    local conditions = {}
    local mileagePenalty = math.min(45, (mileage / 150000) * 45)
    for _, part in ipairs(Config.ConditionParts) do
        local base = 100 - mileagePenalty
        conditions[part] = Utils.Clamp(Utils.Round(base + math.random(-15, 8) - accidentCount * math.random(3, 12)), 5, 100)
    end
    return conditions
end

function ST.NewVehicleCondition()
    local conditions = {}
    for _, part in ipairs(Config.ConditionParts) do conditions[part] = 100 end
    return conditions
end

function ST.InspectVehicle(src, vin)
    local dealershipName = ST.ResolveDealershipForVin(vin)
    if not dealershipName then return false, 'not_found' end
    if not ST.HasPermission(src, dealershipName, 'inspect') then return false, 'no_permission' end
    local row = MySQL.single.await('SELECT mileage, accident_history FROM st_dealership_vehicles WHERE vin = ?', { vin })
    if not row then return false, 'not_found' end
    local accidents = json.decode(row.accident_history or '[]') or {}
    local conditions = rollUsedCondition(row.mileage, #accidents)
    MySQL.update('UPDATE st_dealership_vehicles SET condition_json = ?, inspected = 1 WHERE vin = ?', { json.encode(conditions), vin })
    ST.LogVehicleHistory(vin, 'inspected', { conditions = conditions })
    return true, conditions
end

function ST.ResolveDealershipForVin(vin)
    local row = MySQL.single.await('SELECT dealership FROM st_dealership_vehicles WHERE vin = ?', { vin })
    if not row then return nil, false end
    return row.dealership, true
end

function ST.AcquireVehicle(dealershipName, model, source, overrides)
    overrides = overrides or {}
    local allowedSources = { auction = true, trade_in = true, repo = true, wholesale_in = true, admin = true }
    if not allowedSources[source] then return false, 'invalid_source' end
    local catalog = ST.GetCatalogEntry(model)
    if not catalog then return false, 'unknown_model' end

    local vin = ST.GenerateUniqueVIN()
    if not vin then return false, 'vin_generation_failed' end
    local mileage = tonumber(overrides.mileage) or math.random(500, 95000)
    local conditions = overrides.conditions or rollUsedCondition(mileage, overrides.accidentCount or 0)
    local avgCondition = Utils.AverageCondition(conditions)
    local purchaseCost = tonumber(overrides.purchaseCost) or Utils.Round(catalog.msrp * 0.55)
    local marketPrice = ST.GetMarketPrice(model) or catalog.msrp
    local askingPrice = Utils.Round(marketPrice * (0.6 + (avgCondition / 100) * 0.4))
    local minPrice = Utils.Round(math.max(purchaseCost * 1.02, askingPrice * 0.85))

    local insertedId = MySQL.insert.await([[
        INSERT INTO st_dealership_vehicles
            (vin, dealership, model, mileage, condition_json, purchase_cost, asking_price, min_price,
             acquisition_source, previous_owners, accident_history, title_status, financing_eligible, status, inspected)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'in_stock', 1)
    ]], {
        vin, dealershipName, model, mileage, json.encode(conditions), purchaseCost, askingPrice, minPrice,
        source, overrides.previousOwners or math.random(1, 3), json.encode(overrides.accidents or {}),
        overrides.titleStatus or 'clean', avgCondition >= 40 and 1 or 0,
    })
    if not insertedId then return false, 'insert_failed' end
    if not overrides.skipPayment then ST.AdjustBalance(dealershipName, -purchaseCost, true, 'inventory-acquisition') end
    ST.LogVehicleHistory(vin, 'acquired', { source = source, dealership = dealershipName, cost = purchaseCost })
    return true, { vin = vin, model = model, mileage = mileage, condition = avgCondition, purchaseCost = purchaseCost, askingPrice = askingPrice, minPrice = minPrice }
end
exports('AcquireVehicle', ST.AcquireVehicle)

function ST.AdjustVehiclePrice(src, vin, newAskingPrice)
    local dealershipName = ST.ResolveDealershipForVin(vin)
    if not dealershipName then return false, 'not_found' end
    if not ST.HasPermission(src, dealershipName, 'set_pricing') then return false, 'no_permission' end
    newAskingPrice = math.floor(tonumber(newAskingPrice) or 0)
    if newAskingPrice <= 0 then return false, 'invalid_price' end
    MySQL.update('UPDATE st_dealership_vehicles SET asking_price = ?, min_price = LEAST(min_price, ?) WHERE vin = ?', { newAskingPrice, newAskingPrice, vin })
    return true
end
exports('AdjustVehiclePrice', ST.AdjustVehiclePrice)

-- Inventory lists are intentionally narrow. condition/history/modification
-- blobs can be large; loading them for every vehicle card wastes database
-- bandwidth and JSON decode work. getVehicle remains the detailed endpoint.
local INVENTORY_COLUMNS = [[
    id, vin, dealership, model, plate, mileage, condition_json,
    purchase_cost, asking_price, min_price, acquisition_source,
    previous_owners, title_status, financing_eligible, photos_json, status, inspected
]]

function ST.GetDealershipInventory(dealershipName, statusFilter)
    local query = ('SELECT %s FROM st_dealership_vehicles WHERE dealership = ?'):format(INVENTORY_COLUMNS)
    local params = { dealershipName }
    if statusFilter then query = query .. ' AND status = ?'; params[#params + 1] = statusFilter end
    query = query .. ' ORDER BY updated_at DESC'
    return MySQL.query.await(query, params) or {}
end
exports('GetDealershipInventory', ST.GetDealershipInventory)

function ST.GetVehicleByVin(vin)
    return MySQL.single.await('SELECT * FROM st_dealership_vehicles WHERE vin = ?', { vin })
end
exports('GetVehicleByVin', ST.GetVehicleByVin)

lib.callback.register('st_dealership:server:getInventory', function(src, dealershipName)
    return ST.GetDealershipInventory(dealershipName, 'in_stock')
end)
lib.callback.register('st_dealership:server:getVehicle', function(src, vin)
    return ST.GetVehicleByVin(vin)
end)
lib.callback.register('st_dealership:server:inspectVehicle', function(src, vin)
    return ST.InspectVehicle(src, vin)
end)
lib.callback.register('st_dealership:server:adjustPrice', function(src, vin, newAskingPrice)
    return ST.AdjustVehiclePrice(src, vin, newAskingPrice)
end)
