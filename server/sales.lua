local QBX = exports.qbx_core

--- Evaluates a customer's counteroffer against the vehicle's asking/min
--- price and returns a suggested response. Used by both the negotiation
--- panel (to show the customer a counter) and the kiosk purchase path
--- (to make sure a self-checkout price was actually negotiated fairly).
lib.callback.register('st_dealership:server:evaluateOffer', function(src, vin, offerAmount)
    local vehicle = ST.GetVehicleByVin(vin)
    if not vehicle then return { verdict = 'invalid' } end

    offerAmount = tonumber(offerAmount)
    if not offerAmount then return { verdict = 'invalid' } end

    local asking = tonumber(vehicle.asking_price)
    local minPrice = tonumber(vehicle.min_price)

    if offerAmount >= asking then
        return { verdict = 'accept', counter = asking }
    elseif offerAmount >= minPrice then
        local counter = Utils.Round(minPrice + (asking - minPrice) * 0.6)
        return { verdict = 'counter', counter = math.max(counter, offerAmount) }
    else
        local counter = Utils.Round(minPrice * 1.02)
        return { verdict = 'reject', counter = counter }
    end
end)

--- Every field in `dealOptions` arrives from the client, so none of it is
--- trusted. Financing in particular is re-quoted server-side against the
--- buyer's real credit score - the client's apr/term are discarded, not
--- merely range-checked, so a tampered NUI can't invent a 0% loan.
--- Returns sanitized options, or nil + reason.
local function sanitizeDealOptions(raw, vehicle, finalPrice, buyerCitizenId)
    raw = raw or {}

    local clean = {
        satisfactionRating = nil,
        tradeInVin = nil,
        warranty = type(raw.warranty) == 'table' and raw.warranty or {},
        financed = false,
        downPayment = finalPrice,
        apr = nil,
        termMonths = nil,
    }

    local rating = tonumber(raw.satisfactionRating)
    if rating then clean.satisfactionRating = Utils.Clamp(math.floor(rating), 1, 5) end

    if raw.tradeInVin then
        local tradeIn = ST.GetVehicleByVin(raw.tradeInVin)
        if tradeIn then clean.tradeInVin = tradeIn.vin end
    end

    if not raw.financed then
        return clean
    end

    if not Config.Financing.enabled then return nil, 'financing_disabled' end
    if tonumber(vehicle.financing_eligible) ~= 1 and vehicle.financing_eligible ~= true then
        return nil, 'not_financing_eligible'
    end

    local downPayment = math.floor(tonumber(raw.downPayment) or 0)
    local termMonths = math.floor(tonumber(raw.termMonths) or 36)

    local quote = ST.QuoteFinancing(buyerCitizenId, finalPrice, downPayment, termMonths)
    if not quote.approved then
        return nil, quote.reason or 'financing_declined'
    end

    clean.financed = true
    clean.downPayment = downPayment
    clean.apr = quote.apr
    clean.termMonths = quote.termMonths

    return clean
end

--- Shared completion logic for every sale path (employee-assisted or
--- self-checkout kiosk). `salespersonId` is nil for a kiosk sale - no
--- commission is paid and the dealership keeps the full margin.
---
--- Order matters here: the buyer is charged BEFORE anything is mutated,
--- so a customer who can't actually pay leaves no half-finished sale
--- behind (vehicle marked sold, contract written, no money moved).
local function completeSale(vin, buyerCitizenId, finalPrice, dealOptions, salespersonId)
    local vehicle = ST.GetVehicleByVin(vin)
    if not vehicle then return false, 'not_found' end

    -- 'reserved' means it's held for something else in progress (a
    -- pending financing request, an active auction listing) - it should
    -- never be sellable through this path while that's true, or whichever
    -- process reserved it could get raced by a completely separate sale.
    if vehicle.status ~= 'in_stock' then return false, 'unavailable' end

    finalPrice = math.floor(tonumber(finalPrice) or 0)
    if finalPrice <= 0 then return false, 'invalid_price' end

    -- The negotiation floor is enforced on EVERY path, staff included -
    -- an employee with the 'sell' perm can discount down to min_price and
    -- no further, which is what the negotiation engine already told the
    -- customer.
    local minPrice = math.floor(tonumber(vehicle.min_price) or 0)
    if finalPrice < minPrice then return false, 'below_minimum' end

    local dealershipName = vehicle.dealership

    local clean, reason = sanitizeDealOptions(dealOptions, vehicle, finalPrice, buyerCitizenId)
    if not clean then return false, reason end

    -- What the customer actually hands over right now.
    local amountDue = finalPrice
    if clean.financed and Config.Money.financedChargesDownPaymentOnly then
        amountDue = clean.downPayment
    end

    if amountDue > 0 then
        if not ST.Money.CanPlayerAfford(buyerCitizenId, amountDue) then
            return false, 'insufficient_funds'
        end
        local paid = ST.Money.RemovePlayer(buyerCitizenId, amountDue, 'vehicle-purchase')
        if not paid then return false, 'insufficient_funds' end
    end

    MySQL.update("UPDATE st_dealership_vehicles SET status = 'sold' WHERE vin = ?", { vin })
    ST.ClearDisplayAssignmentForVin(dealershipName, vin)

    local contractId = MySQL.insert.await([[
        INSERT INTO st_dealership_contracts
            (vin, dealership, buyer_citizenid, salesperson_citizenid, sale_price, trade_in_vin,
             down_payment, financed, apr, term_months, warranty_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        vin, dealershipName, buyerCitizenId, salespersonId, finalPrice, clean.tradeInVin,
        clean.downPayment, clean.financed and 1 or 0,
        clean.apr, clean.termMonths, json.encode(clean.warranty),
    })

    ST.LogVehicleHistory(vin, 'sold', { buyer = buyerCitizenId, price = finalPrice, contractId = contractId, salesperson = salespersonId })

    ST.AdjustBalance(dealershipName, amountDue, true, 'vehicle-sale')

    if clean.financed then
        ST.OpenLoan(contractId, buyerCitizenId, vin, finalPrice - clean.downPayment, clean.apr, clean.termMonths)
    end

    -- Registers ownership with qbx_vehicles (if installed) so the vehicle
    -- persists in the buyer's garage, and hands them a drivable copy right
    -- now if they're online and a purchase-spawn point can be resolved.
    -- Falls back to a non-persistent spawn if qbx_vehicles isn't running.
    ST.HandOverPurchasedVehicle(buyerCitizenId, dealershipName, vehicle.model, vin)

    if salespersonId then
        local meta = {
            satisfaction = clean.satisfactionRating,
            financed = clean.financed,
            tradeIn = clean.tradeInVin ~= nil,
            daysOnLot = tonumber(vehicle.days_on_lot) or 0,
        }
        ST.RecordEmployeeSale(salespersonId, dealershipName, finalPrice, meta)
        ST.PayCommission(salespersonId, dealershipName, finalPrice, meta)
    end

    ST.AdjustReputation(dealershipName, {
        pricing = (finalPrice >= minPrice and finalPrice <= tonumber(vehicle.asking_price)) and 0.5 or -0.5,
        customer_service = clean.satisfactionRating and ((clean.satisfactionRating - 3) * 1.5) or 0,
    })

    return true, { contractId = contractId, dealership = dealershipName, charged = amountDue, financed = clean.financed }
end
ST.CompleteSale = completeSale -- exposed for server/financingrequests.lua's approval flow

--- Employee-assisted sale: requires the acting player (`src`) to hold the
--- 'sell' permission at the vehicle's dealership. Commission is paid to
--- `src`. This is the path the Dealership Ops console uses to close a deal
--- on a customer's behalf.
function ST.SellVehicle(src, vin, buyerCitizenId, finalPrice, dealOptions)
    local vehicle = ST.GetVehicleByVin(vin)
    if not vehicle then return false, 'not_found' end
    if not ST.HasPermission(src, vehicle.dealership, 'sell') then return false, 'no_permission' end

    -- The buyer has to be a real, online character - not an arbitrary
    -- string the Ops console was talked into sending, and not someone
    -- offline who'd be charged with no way to see or refuse it.
    if not buyerCitizenId or not QBX:GetPlayerByCitizenId(buyerCitizenId) then
        return false, 'buyer_offline'
    end

    return completeSale(vin, buyerCitizenId, finalPrice, dealOptions, ST.GetPlayerCitizenId(src))
end
exports('SellVehicle', ST.SellVehicle)

lib.callback.register('st_dealership:server:sellVehicle', function(src, vin, buyerCitizenId, finalPrice, dealOptions)
    return ST.SellVehicle(src, vin, buyerCitizenId, finalPrice, dealOptions)
end)

--- Self-checkout: any player can buy directly from the showroom kiosk with
--- no employee online, but only at a price the negotiation engine would
--- actually accept - the floor is re-checked inside completeSale so a
--- player can never talk the NUI into a below-minimum price, and the
--- financing terms are re-quoted there too. No commission is paid.
lib.callback.register('st_dealership:server:kioskPurchase', function(src, vin, finalPrice, dealOptions)
    local buyerCitizenId = ST.GetPlayerCitizenId(src)
    if not buyerCitizenId then return false, 'no_player' end

    return completeSale(vin, buyerCitizenId, finalPrice, dealOptions, nil)
end)
