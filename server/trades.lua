local QBX = exports.qbx_core

-- ---------------------------------------------------------------------------
-- Trade-in appraisal
--
-- Everything the client sends about the vehicle is a suggestion, not a fact.
-- Mileage and condition are derived server-side from a stable hash of the
-- plate, so:
--   * a tampered client can't claim 0 miles / 100% condition to inflate the
--     payout, and
--   * re-appraising the same car repeatedly gives the same answer instead
--     of letting a player reroll until the number is good.
-- If you track real odometer/condition data in another resource, replace
-- derivedMileage/derivedCondition below with a call into it - the rest of
-- the flow already reads from the offer row rather than from the client.
-- ---------------------------------------------------------------------------

local function stableSeed(plate, salt)
    local seed = 0
    local s = tostring(plate or '') .. tostring(salt or '')
    for i = 1, #s do
        seed = (seed * 31 + s:byte(i)) % 2147483647
    end
    return seed
end

local function derivedMileage(plate)
    return 5000 + (stableSeed(plate, 'mileage') % 175000)
end

local function derivedCondition(plate, mileage)
    local conditions = {}
    local mileagePenalty = math.min(45, (mileage / 150000) * 45)
    for i, part in ipairs(Config.ConditionParts) do
        local variance = (stableSeed(plate, 'cond' .. i) % 24) - 15 -- -15..+8
        conditions[part] = Utils.Clamp(Utils.Round(100 - mileagePenalty + variance), 5, 100)
    end
    return conditions
end

--- Confirms the player is genuinely in/at the vehicle they're appraising,
--- and that its plate is what they claim. Without this the whole appraisal
--- was a client-supplied string.
local function verifyPlayerVehicle(src, playerVehicle)
    if type(playerVehicle) ~= 'table' then return nil end

    local netId = tonumber(playerVehicle.netId)
    if not netId then return nil end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end

    -- Seated in it, or standing right next to it (appraisals happen with
    -- the car parked on the lot, so both are legitimate).
    if GetVehiclePedIsIn(ped) ~= entity then
        local pedCoords = GetEntityCoords(ped)
        local vehCoords = GetEntityCoords(entity)
        if #(pedCoords - vehCoords) > 6.0 then return nil end
    end

    local plate = (GetVehicleNumberPlate(entity) or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if plate == '' then return nil end

    return entity, plate
end

lib.callback.register('st_dealership:server:appraiseTradeIn', function(src, dealershipName, playerVehicle)
    if not ST.GetDealership(dealershipName) then return { error = 'unknown_dealership' } end

    local entity, plate = verifyPlayerVehicle(src, playerVehicle)
    if not entity then return { error = 'vehicle_not_verified' } end

    local catalog = ST.GetCatalogEntry(playerVehicle.model)
    if not catalog then return { error = 'unknown_model' } end

    -- The claimed model has to match the entity actually sitting there.
    if GetEntityModel(entity) ~= joaat(playerVehicle.model) then
        return { error = 'unknown_model' }
    end

    local mileage = derivedMileage(plate)
    local conditions = derivedCondition(plate, mileage)
    local avgCondition = Utils.AverageCondition(conditions)

    local marketPrice = ST.GetMarketPrice(playerVehicle.model) or catalog.msrp
    local mileageFactor = Utils.Clamp(1.0 - (mileage / 200000), 0.35, 1.0)
    local conditionFactor = 0.5 + (avgCondition / 100) * 0.5

    local marketValue = Utils.Round(marketPrice * mileageFactor * conditionFactor)

    local dealership = ST.GetDealership(dealershipName)
    local margin = (dealership and dealership.rules and dealership.rules.marginTarget) or 0.18
    local offerAmount = Utils.Round(marketValue * (1 - margin))

    local citizenId = ST.GetPlayerCitizenId(src)
    if not citizenId then return { error = 'no_player' } end

    -- One open offer per plate per dealership - re-appraising replaces the
    -- previous pending offer rather than stacking a second claimable one.
    MySQL.update("UPDATE st_dealership_tradein_offers SET status = 'expired' WHERE citizenid = ? AND plate = ? AND status = 'pending'",
        { citizenId, plate })

    local offerId = MySQL.insert.await([[
        INSERT INTO st_dealership_tradein_offers
            (dealership, citizenid, plate, model, mileage, condition_json, appraised_value, offer_amount)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { dealershipName, citizenId, plate, playerVehicle.model, mileage, json.encode(conditions), marketValue, offerAmount })

    return {
        offerId = offerId, marketValue = marketValue, offerAmount = offerAmount,
        mileage = mileage, condition = avgCondition,
    }
end)

--- Customer accepts a trade-in offer: the dealership pays out to the
--- customer, and the vehicle enters inventory as used stock carrying the
--- mileage and condition it was actually appraised at.
lib.callback.register('st_dealership:server:acceptTradeIn', function(src, offerId)
    local citizenId = ST.GetPlayerCitizenId(src)
    if not citizenId then return false, 'no_player' end

    local offer = MySQL.single.await("SELECT * FROM st_dealership_tradein_offers WHERE id = ? AND status = 'pending'", { offerId })
    if not offer then return false, 'not_found' end

    -- Ownership check: previously ANY player could accept ANY pending
    -- offer, which both stole the payout and drained the dealership.
    if offer.citizenid ~= citizenId then return false, 'not_your_offer' end

    local payout = math.floor(tonumber(offer.offer_amount) or 0)
    if payout <= 0 then return false, 'invalid_offer' end

    -- Unlike acquisitions, a trade-in is NOT allowed to overdraw: the
    -- dealership is handing cash to a customer, so it has to actually
    -- have it.
    if not ST.AdjustBalance(offer.dealership, -payout, false, 'trade-in-payout') then
        return false, 'insufficient_funds'
    end

    if not ST.Money.AddPlayer(citizenId, payout, 'vehicle-trade-in') then
        -- Roll the dealership debit back rather than swallowing the payout.
        ST.AdjustBalance(offer.dealership, payout, true, 'trade-in-payout-reversal')
        return false, 'payout_failed'
    end

    MySQL.update("UPDATE st_dealership_tradein_offers SET status = 'accepted' WHERE id = ?", { offerId })

    -- The physical vehicle gets deleted from the world client-side once
    -- this returns (see client/nui.lua's acceptTradeIn callback) - if it
    -- was a qbx_vehicles-owned vehicle, clear that ownership record too,
    -- otherwise it'd keep showing up in the trader's garage as a car that
    -- no longer exists anywhere.
    if GetResourceState('qbx_vehicles') == 'started' and offer.plate then
        pcall(function() exports.qbx_vehicles:DeletePlayerVehicles('plate', offer.plate) end)
    end

    local conditions = nil
    if offer.condition_json then
        local ok, decoded = pcall(json.decode, offer.condition_json)
        if ok then conditions = decoded end
    end

    -- mileage/conditions come from the appraisal, not from a hardcoded 0.
    -- Passing mileage = 0 (as this did before) made AcquireVehicle treat
    -- every trade-in as factory-new and reset all condition parts to 100.
    local ok, vehicleData = ST.AcquireVehicle(offer.dealership, offer.model, 'trade_in', {
        mileage = tonumber(offer.mileage) or 0,
        conditions = conditions,
        purchaseCost = payout,
        previousOwners = 1,
        skipPayment = true, -- the customer was just paid directly, above
    })

    return ok, { payout = payout, vehicle = vehicleData }
end)

-- ---------------------------------------------------------------------------
-- Dealer-to-dealer trading
-- ---------------------------------------------------------------------------

--- Transfers a vehicle from one dealership's inventory to another, optionally
--- with a cash adjustment from `fromDealership` to `toDealership` (or
--- negative for the reverse). Requires 'purchase_inventory' perm on the
--- initiating dealership.
function ST.TransferInventory(src, fromDealership, toDealership, vin, cashAdjustment)
    if not ST.HasPermission(src, fromDealership, 'purchase_inventory') then return false, 'no_permission' end
    if not ST.GetDealership(toDealership) then return false, 'target_not_found' end

    local vehicle = ST.GetVehicleByVin(vin)
    if not vehicle or vehicle.dealership ~= fromDealership then return false, 'not_found' end

    MySQL.update('UPDATE st_dealership_vehicles SET dealership = ? WHERE vin = ?', { toDealership, vin })

    cashAdjustment = math.floor(tonumber(cashAdjustment) or 0)
    if cashAdjustment ~= 0 then
        ST.AdjustBalance(toDealership, -cashAdjustment, true, 'dealer-transfer')
        ST.AdjustBalance(fromDealership, cashAdjustment, true, 'dealer-transfer')
    end

    ST.LogVehicleHistory(vin, 'dealer_transfer', { from = fromDealership, to = toDealership, cashAdjustment = cashAdjustment })
    return true
end
exports('TransferInventory', ST.TransferInventory)

lib.callback.register('st_dealership:server:transferInventory', function(src, fromDealership, toDealership, vin, cashAdjustment)
    return ST.TransferInventory(src, fromDealership, toDealership, vin, cashAdjustment)
end)
